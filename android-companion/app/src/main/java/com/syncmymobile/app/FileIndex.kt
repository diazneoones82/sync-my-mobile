package com.syncmymobile.app

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import java.net.HttpURLConnection
import java.net.URL

data class SharedFile(
    val id: String,
    val relativePath: String,
    val size: Long,
    val modified: Long,
)

class FileIndex(private val context: Context) {
    fun files(): List<SharedFile> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val folders = prefs
            .getStringSet(PREF_FOLDERS, emptySet())
            .orEmpty()
        val selectedFiles = prefs
            .getStringSet(PREF_FILES, emptySet())
            .orEmpty()
        val links = prefs
            .getStringSet(PREF_LINKS, emptySet())
            .orEmpty()

        val folderFiles = folders.flatMap { folder ->
            val uri = Uri.parse(folder)
            if (DocumentsContract.isTreeUri(uri)) {
                val tree = DocumentFile.fromTreeUri(context, uri) ?: return@flatMap emptyList()
                walk(tree, rootLabel(uri, tree), "")
            } else {
                val document = DocumentFile.fromSingleUri(context, uri) ?: return@flatMap emptyList()
                walkDocumentUri(uri, rootLabel(uri, document), "")
            }
        }

        val singleFiles = selectedFiles.mapNotNull { file ->
            val uri = Uri.parse(file)
            val document = DocumentFile.fromSingleUri(context, uri) ?: return@mapNotNull null
            if (!document.isFile) return@mapNotNull null
            val provider = providerLabel(uri)
            SharedFile(
                id = document.uri.toString(),
                relativePath = listOfNotNull(provider, document.name ?: "unnamed").joinToString("/"),
                size = document.length(),
                modified = document.lastModified(),
            )
        }

        val linkedFiles = links.map { link ->
            val normalized = normalizeCloudLink(link)
            SharedFile(
                id = "url:$normalized",
                relativePath = "${providerLabel(Uri.parse(link)) ?: "Cloud Links"}/${linkFileName(normalized, link, providerLabel(Uri.parse(link)))}",
                size = 0,
                modified = 0,
            )
        }

        return (folderFiles + singleFiles + linkedFiles).distinctBy { it.relativePath.lowercase() }
    }

    fun manifestJson(): String {
        val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
        val interval = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(PREF_AUTO_INTERVAL, 15)
        val entries = files().joinToString(",") { file ->
            """{"id":"${json(file.id)}","relativePath":"${json(file.relativePath)}","size":${file.size},"modified":${file.modified}}"""
        }
        return """{"app":"$APP_ID","deviceName":"${json(deviceName)}","autoIntervalMinutes":$interval,"files":[$entries]}"""
    }

    private fun walk(file: DocumentFile, rootName: String, prefix: String): List<SharedFile> {
        if (file.isFile) {
            val name = file.name ?: "unnamed"
            return listOf(
                SharedFile(
                    id = file.uri.toString(),
                    relativePath = listOf(rootName, prefix, name).filter { it.isNotBlank() }.joinToString("/"),
                    size = file.length(),
                    modified = file.lastModified(),
                ),
            )
        }

        if (!file.isDirectory) return emptyList()

        val nextPrefix = if (prefix.isBlank()) "" else "$prefix/"
        return file.listFiles().flatMap { child ->
            if (child.isDirectory) {
                walk(child, rootName, nextPrefix + (child.name ?: "Folder"))
            } else {
                walk(child, rootName, prefix)
            }
        }
    }

    private fun walkDocumentUri(uri: Uri, rootName: String, prefix: String): List<SharedFile> {
        val document = DocumentFile.fromSingleUri(context, uri) ?: return emptyList()
        if (document.isFile) {
            val name = document.name ?: "unnamed"
            return listOf(
                SharedFile(
                    id = document.uri.toString(),
                    relativePath = listOf(rootName, prefix, name).filter { it.isNotBlank() }.joinToString("/"),
                    size = document.length(),
                    modified = document.lastModified(),
                ),
            )
        }
        if (!document.isDirectory) return emptyList()

        val authority = uri.authority ?: return emptyList()
        val parentId = runCatching { DocumentsContract.getDocumentId(uri) }.getOrNull() ?: return emptyList()
        val childrenUri = DocumentsContract.buildChildDocumentsUri(authority, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val children = mutableListOf<SharedFile>()
        context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val childId = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: "unnamed"
                val mime = cursor.getString(mimeIndex)
                val childUri = DocumentsContract.buildDocumentUri(authority, childId)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val nextPrefix = if (prefix.isBlank()) name else "$prefix/$name"
                    children += walkDocumentUri(childUri, rootName, nextPrefix)
                } else {
                    children += SharedFile(
                        id = childUri.toString(),
                        relativePath = listOf(rootName, prefix, name).filter { it.isNotBlank() }.joinToString("/"),
                        size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else 0,
                        modified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) cursor.getLong(modifiedIndex) else 0,
                    )
                }
            }
        }
        return children
    }

    private fun json(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
    }

    private fun rootLabel(uri: Uri, file: DocumentFile): String {
        val provider = providerLabel(uri)
        return listOfNotNull(provider, file.name).joinToString(" - ").ifBlank { "Phone" }
    }

    private fun providerLabel(uri: Uri): String? {
        return when {
            uri.authority?.contains("onedrive", ignoreCase = true) == true ||
                uri.authority?.contains("skydrive", ignoreCase = true) == true ||
                uri.authority?.contains("microsoft", ignoreCase = true) == true ||
                uri.authority?.contains("1drv.ms", ignoreCase = true) == true ||
                uri.authority?.contains("sharepoint", ignoreCase = true) == true -> "OneDrive"
            uri.authority?.contains("box", ignoreCase = true) == true -> "Box"
            uri.authority?.contains("docs.google", ignoreCase = true) == true ||
                uri.authority?.contains("google", ignoreCase = true) == true ||
                uri.authority?.contains("drive", ignoreCase = true) == true -> "Google Drive"
            else -> null
        }
    }

    private fun normalizeCloudLink(link: String): String {
        val uri = Uri.parse(link.trim())
        if (uri.authority?.contains("drive.google", ignoreCase = true) == true) {
            val id = Regex("""/d/([^/]+)""").find(link)?.groupValues?.getOrNull(1)
                ?: uri.getQueryParameter("id")
            if (!id.isNullOrBlank()) {
                return "https://drive.google.com/uc?export=download&id=$id"
            }
        }
        if (uri.authority?.contains("1drv.ms", ignoreCase = true) == true ||
            uri.authority?.contains("onedrive.live.com", ignoreCase = true) == true
        ) {
            val encoded = android.util.Base64.encodeToString(
                link.trim().toByteArray(),
                android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP,
            )
            return "https://api.onedrive.com/v1.0/shares/u!$encoded/root/content"
        }
        return link.trim()
    }

    private fun linkFileName(normalized: String, original: String, provider: String?): String {
        if (provider == "Google Drive") {
            googleDriveFileName(original)?.let { return it }
        }
        val uri = Uri.parse(original)
        val host = uri.host ?: "cloud-link"
        val last = uri.lastPathSegment?.takeIf { it.isNotBlank() && it != "view" } ?: Uri.parse(normalized).lastPathSegment ?: "download"
        return "$host-$last"
            .replace(Regex("""[^\w.\- ]"""), "_")
            .take(120)
    }

    private fun googleDriveFileName(link: String): String? {
        val uri = Uri.parse(link)
        val id = Regex("""/d/([^/]+)""").find(link)?.groupValues?.getOrNull(1)
            ?: uri.getQueryParameter("id")
            ?: return null
        return try {
            val metadataUrl = URL("https://drive.google.com/uc?export=download&id=$id")
            val connection = metadataUrl.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 SyncMyMobile/0.1")
            val disposition = connection.getHeaderField("Content-Disposition")
            filenameFromDisposition(disposition)
        } catch (_: Exception) {
            null
        }
    }

    private fun filenameFromDisposition(value: String?): String? {
        if (value.isNullOrBlank()) return null
        val match = Regex("""filename\*?=(?:UTF-8''|")?([^";]+)""", RegexOption.IGNORE_CASE).find(value)
            ?: return null
        return java.net.URLDecoder.decode(match.groupValues[1].trim('"'), "UTF-8")
            .replace(Regex("""[^\w.\- ]"""), "_")
            .takeIf { it.isNotBlank() }
    }
}
