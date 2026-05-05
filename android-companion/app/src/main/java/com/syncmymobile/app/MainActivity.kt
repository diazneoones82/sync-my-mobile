package com.syncmymobile.app

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : Activity() {
    private lateinit var folderList: TextView
    private lateinit var intervalInput: EditText
    private lateinit var dateTimeFooter: TextView
    private val pendingCloudSelections = ArrayDeque<SafSelection>()
    private val clockHandler = Handler(Looper.getMainLooper())
    private val clockRunnable = object : Runnable {
        override fun run() {
            if (::dateTimeFooter.isInitialized) {
                dateTimeFooter.text = footerDateTime()
            }
            clockHandler.postDelayed(this, 100)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
        setContentView(buildView())
        refreshFolderText()
        handleOAuthRedirect(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        handleOAuthRedirect(intent)
    }

    override fun onDestroy() {
        clockHandler.removeCallbacks(clockRunnable)
        super.onDestroy()
    }

    @Deprecated("Used for broad Android Studio compatibility in this small starter project.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_TREE && requestCode != REQUEST_FILES) return

        if (resultCode == RESULT_OK) {
            if (requestCode == REQUEST_TREE) {
                persistTreeResult(data)
            } else {
                persistFileResult(data)
            }
        }

        if (pendingCloudSelections.isNotEmpty()) {
            openSafSelection(pendingCloudSelections.removeFirst())
        }
    }

    private fun buildView(): ScrollView {
        val dark = prefs().getBoolean(PREF_DARK_MODE, true)
        val bg = if (dark) Color.rgb(7, 17, 31) else Color.rgb(245, 249, 255)
        val panel = if (dark) Color.rgb(11, 23, 41) else Color.WHITE
        val fg = if (dark) Color.rgb(230, 247, 255) else Color.rgb(16, 32, 51)
        val accent = if (dark) Color.rgb(115, 246, 255) else Color.rgb(37, 99, 235)

        val scroll = ScrollView(this)
        scroll.setBackgroundColor(bg)

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.gravity = Gravity.CENTER_HORIZONTAL
        root.setPadding(36, 48, 36, 36)
        root.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        root.setBackgroundColor(bg)

        val logo = ImageView(this)
        logo.setImageResource(resources.getIdentifier("ic_launcher", "mipmap", packageName))
        logo.layoutParams = LinearLayout.LayoutParams(144, 144)
        root.addView(logo)

        val title = TextView(this)
        title.text = "Sync My Mobile"
        title.textSize = 26f
        title.setTextColor(fg)
        root.addView(title)

        val accentText = TextView(this)
        accentText.text = "Neo Apps"
        accentText.textSize = 13f
        accentText.setTextColor(accent)
        accentText.setPadding(0, 4, 0, 18)
        root.addView(accentText)

        val darkToggle = Switch(this)
        darkToggle.text = "Dark Mode"
        darkToggle.isChecked = dark
        darkToggle.setTextColor(fg)
        darkToggle.setOnCheckedChangeListener { _, isChecked ->
            prefs().edit().putBoolean(PREF_DARK_MODE, isChecked).apply()
            setContentView(buildView())
            refreshFolderText()
        }
        root.addView(darkToggle)

        folderList = TextView(this)
        folderList.textSize = 15f
        folderList.setTextColor(fg)
        folderList.setBackgroundColor(panel)
        folderList.setPadding(0, 32, 0, 32)
        root.addView(folderList)

        val addFolder = Button(this)
        addFolder.text = "Add Phone Internal Storage"
        addFolder.setOnClickListener { openFolderPicker("Select a phone, cloud, or document-provider folder") }
        root.addView(addFolder)

        val addSource = Button(this)
        addSource.text = "Choose Source"
        addSource.setOnClickListener { showSourceChooser() }
        root.addView(addSource)

        val cloudButtons = LinearLayout(this)
        cloudButtons.orientation = LinearLayout.VERTICAL
        cloudButtons.gravity = Gravity.CENTER_HORIZONTAL
        CLOUD_PROVIDERS.forEach { provider ->
            val button = Button(this)
            button.text = "Open ${provider.name}"
            button.setOnClickListener { launchCloudApp(provider) }
            cloudButtons.addView(button)
        }
        root.addView(cloudButtons)

        val clearFolders = Button(this)
        clearFolders.text = "Clear Selections"
        clearFolders.setOnClickListener {
            prefs().edit().remove(PREF_FOLDERS).remove(PREF_FILES).remove(PREF_LINKS).apply()
            refreshFolderText()
        }
        root.addView(clearFolders)

        intervalInput = EditText(this)
        intervalInput.setText(prefs().getInt(PREF_AUTO_INTERVAL, 1).toString())
        intervalInput.hint = "Auto interval minutes"
        intervalInput.setSingleLine(true)
        intervalInput.setTextColor(fg)
        intervalInput.setHintTextColor(accent)
        intervalInput.setBackgroundColor(panel)
        intervalInput.setPadding(20, 12, 20, 12)
        root.addView(intervalInput)

        val saveInterval = Button(this)
        saveInterval.text = "Save Interval"
        saveInterval.setOnClickListener { saveInterval() }
        root.addView(saveInterval)

        val start = Button(this)
        start.text = "Start LAN Sync"
        start.setOnClickListener {
            saveInterval()
            val intent = Intent(this, SyncService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            Toast.makeText(this, "LAN sync started on port $HTTP_PORT", Toast.LENGTH_LONG).show()
        }
        root.addView(start)

        val stop = Button(this)
        stop.text = "Stop Sync"
        stop.setOnClickListener {
            stopService(Intent(this, SyncService::class.java))
            Toast.makeText(this, "Sync has stopped", Toast.LENGTH_LONG).show()
        }
        root.addView(stop)

        val settings = Button(this)
        settings.text = "App Settings"
        settings.setOnClickListener {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
        root.addView(settings)

        val about = Button(this)
        about.text = "About"
        about.setOnClickListener { showAbout() }
        root.addView(about)

        val cloudHelp = Button(this)
        cloudHelp.text = "Cloud Access Help"
        cloudHelp.setOnClickListener { showCloudHelp() }
        root.addView(cloudHelp)

        val exit = Button(this)
        exit.text = "Exit"
        exit.setOnClickListener { exitApp() }
        root.addView(exit)

        dateTimeFooter = TextView(this)
        dateTimeFooter.textSize = 14f
        dateTimeFooter.setTextColor(accent)
        dateTimeFooter.gravity = Gravity.CENTER
        dateTimeFooter.setPadding(0, 30, 0, 0)
        root.addView(dateTimeFooter)
        startFooterClock()

        scroll.addView(root)
        return scroll
    }

    private fun startFooterClock() {
        clockHandler.removeCallbacks(clockRunnable)
        dateTimeFooter.text = footerDateTime()
        clockHandler.postDelayed(clockRunnable, 100)
    }

    private fun footerDateTime(): String {
        return SimpleDateFormat("EEEE, yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())
    }

    private fun exitApp() {
        stopService(Intent(this, SyncService::class.java))
        clockHandler.removeCallbacks(clockRunnable)
        finishAndRemoveTask()
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    private fun openFolderPicker(title: String, providerPackage: String? = null) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        intent.putExtra(Intent.EXTRA_TITLE, title)
        intent.putExtra("android.content.extra.SHOW_ADVANCED", true)
        try {
            if (providerPackage != null) {
                Toast.makeText(this, "Use the picker side menu to choose the cloud provider", Toast.LENGTH_LONG).show()
            }
            startActivityForResult(intent, REQUEST_TREE)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, "No folder picker is available on this device", Toast.LENGTH_LONG).show()
        }
    }

    private fun showSourceChooser() {
        val options = arrayOf(
            "Phone Internal Storage",
            "Cloud Files",
        )
        AlertDialog.Builder(this)
            .setTitle("Choose source")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> openFolderPicker("Select phone internal storage folder")
                    else -> openFilePicker("Select cloud files")
                }
            }
            .show()
    }

    private fun showOAuthChooser() {
        val providers = CloudOAuth.providers(this)
        val labels = providers.map { provider ->
            val status = if (CloudOAuth.accessToken(this, provider.id).isNullOrBlank()) "not connected" else "connected"
            "${provider.displayName} ($status)"
        }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Connect cloud account")
            .setItems(labels) { _, which -> startOAuth(providers[which]) }
            .show()
    }

    private fun startOAuth(provider: OAuthProvider) {
        if (!CloudOAuth.isConfigured(provider)) {
            AlertDialog.Builder(this)
                .setTitle("${provider.displayName} setup needed")
                .setMessage(
                    "OAuth client ID is not configured yet.\n\n" +
                        "Create an OAuth app in the provider developer console, add redirect URI ${getString(R.string.oauth_redirect_uri)}, then replace the placeholder client ID in strings.xml.",
                )
                .setPositiveButton("OK", null)
                .show()
            return
        }
        try {
            startActivity(CloudOAuth.authIntent(this, provider))
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, "No browser available for OAuth sign-in", Toast.LENGTH_LONG).show()
        }
    }

    private fun handleOAuthRedirect(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != getString(R.string.oauth_redirect_scheme) || uri.host != "oauth") return
        val providerId = uri.getQueryParameter("state")?.let { runCatching { CloudProviderId.valueOf(it) }.getOrNull() }
            ?: return
        val error = uri.getQueryParameter("error")
        if (!error.isNullOrBlank()) {
            Toast.makeText(this, "OAuth failed: $error", Toast.LENGTH_LONG).show()
            return
        }
        val code = uri.getQueryParameter("code") ?: return
        val provider = CloudOAuth.provider(this, providerId)
        Thread {
            try {
                CloudOAuth.exchangeCode(this, provider, code)
                runOnUiThread {
                    Toast.makeText(this, "${provider.displayName} connected", Toast.LENGTH_LONG).show()
                }
            } catch (exc: Exception) {
                runOnUiThread {
                    AlertDialog.Builder(this)
                        .setTitle("${provider.displayName} OAuth failed")
                        .setMessage(exc.message ?: "Unknown error")
                        .setPositiveButton("OK", null)
                        .show()
                }
            }
        }.start()
    }

    private fun launchCloudApp(provider: CloudProvider) {
        val intent = packageManager.getLaunchIntentForPackage(provider.packageName)
        if (intent != null) {
            startActivity(intent)
        } else {
            Toast.makeText(this, "${provider.name} is not installed", Toast.LENGTH_LONG).show()
        }
    }

    private fun openSafSelection(selection: SafSelection) {
        Toast.makeText(this, "Choose ${selection.providerName} from the picker side menu", Toast.LENGTH_LONG).show()
        if (selection.mode == CloudMode.FOLDER) {
            openFolderPicker("Select a ${selection.providerName} folder", selection.providerPackage)
        } else {
            openFilePicker("Select ${selection.providerName} files", selection.providerPackage)
        }
    }

    private fun openFilePicker(title: String, providerPackage: String? = null) {
        val providerName = providerPackage?.let { packageName ->
            CLOUD_PROVIDERS.firstOrNull { it.packageName == packageName }?.name
        }
        if (providerName != null) {
            Toast.makeText(this, "Use Open from to choose $providerName, then select files", Toast.LENGTH_LONG).show()
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.type = "*/*"
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        intent.putExtra(Intent.EXTRA_TITLE, title)
        intent.putExtra(Intent.EXTRA_LOCAL_ONLY, false)
        intent.putExtra("android.content.extra.SHOW_ADVANCED", true)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        try {
            startActivityForResult(intent, REQUEST_FILES)
        } catch (_: ActivityNotFoundException) {
            try {
                val fallback = Intent(Intent.ACTION_GET_CONTENT)
                fallback.addCategory(Intent.CATEGORY_OPENABLE)
                fallback.type = "*/*"
                fallback.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                startActivityForResult(Intent.createChooser(fallback, title), REQUEST_FILES)
            } catch (_: ActivityNotFoundException) {
                Toast.makeText(this, "No file picker is available on this device", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun saveFolder(uri: Uri) {
        val current = prefs().getStringSet(PREF_FOLDERS, emptySet())?.toMutableSet() ?: mutableSetOf()
        current.add(uri.toString())
        prefs().edit().putStringSet(PREF_FOLDERS, current).apply()
    }

    private fun saveFile(uri: Uri) {
        val current = prefs().getStringSet(PREF_FILES, emptySet())?.toMutableSet() ?: mutableSetOf()
        current.add(uri.toString())
        prefs().edit().putStringSet(PREF_FILES, current).apply()
    }

    private fun refreshFolderText() {
        val folders = prefs()
            .getStringSet(PREF_FOLDERS, emptySet())
            .orEmpty()
            .sorted()
        val files = prefs()
            .getStringSet(PREF_FILES, emptySet())
            .orEmpty()
            .sorted()
        val labels = (folders.map { simpleTreeLabel(Uri.parse(it)) } + fileCountLabels(files.map { Uri.parse(it) }))
            .distinct()
            .sorted()
        folderList.text = if (labels.isEmpty()) {
            "No folders or files selected yet."
        } else {
            "Selected:\n" + labels.joinToString("\n")
        }
    }

    private fun persistTreeResult(data: Intent?) {
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        data?.data?.let { uris.add(it) }
        if (uris.isEmpty()) return
        val flags = (data?.flags ?: 0) and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        var saved = 0
        uris.distinct().forEach { uri ->
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
                saveFolder(uri)
                saved += 1
            } catch (exc: SecurityException) {
                Toast.makeText(this, "Could not keep folder access: ${exc.message}", Toast.LENGTH_LONG).show()
            }
        }
        refreshFolderText()
        if (saved > 0) Toast.makeText(this, "$saved folder(s) selected", Toast.LENGTH_SHORT).show()
    }

    private fun persistFileResult(data: Intent?) {
        val flags = data?.flags?.and(Intent.FLAG_GRANT_READ_URI_PERMISSION) ?: 0
        val uris = mutableListOf<Uri>()
        val clipData = data?.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        data?.data?.let { uris.add(it) }
        uris.distinct().forEach { uri ->
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
                saveFile(uri)
            } catch (_: SecurityException) {
                saveFile(uri)
            }
        }
        refreshFolderText()
        val summary = fileCountLabels(uris.distinct()).joinToString("\n").ifBlank {
            "${uris.distinct().size} file(s) selected"
        }
        Toast.makeText(this, summary, Toast.LENGTH_LONG).show()
    }

    private fun simpleTreeLabel(uri: Uri): String {
        val provider = providerName(uri)
        val raw = uri.lastPathSegment?.substringAfterLast(":")?.substringAfterLast("/")?.takeIf { it.isNotBlank() }
        return listOfNotNull(provider, raw ?: "Folder").joinToString(" - ")
    }

    private fun fileCountLabels(uris: Collection<Uri>): List<String> {
        val counts = linkedMapOf<String, Int>()
        uris.forEach { uri ->
            val label = providerCountName(uri)
            counts[label] = (counts[label] ?: 0) + 1
        }
        return counts.map { (provider, count) -> "$provider: $count file(s) selected" }
    }

    private fun providerCountName(uri: Uri): String {
        val authority = uri.authority.orEmpty()
        return when {
            authority.contains("skydrive", ignoreCase = true) ||
                authority.contains("onedrive", ignoreCase = true) ||
                authority.contains("microsoft", ignoreCase = true) ||
                authority.contains("sharepoint", ignoreCase = true) -> "ONEDRIVE"
            authority.contains("box", ignoreCase = true) -> "BOXDRIVE"
            authority.contains("docs.google", ignoreCase = true) ||
                authority.contains("google", ignoreCase = true) ||
                authority.contains("drive", ignoreCase = true) -> "GDRIVE"
            else -> "Cloud Files"
        }
    }

    private fun providerName(uri: Uri): String? {
        val authority = uri.authority.orEmpty()
        return when {
            authority.contains("skydrive", ignoreCase = true) ||
                authority.contains("onedrive", ignoreCase = true) ||
                authority.contains("microsoft", ignoreCase = true) ||
                authority.contains("sharepoint", ignoreCase = true) -> "OneDrive"
            authority.contains("box", ignoreCase = true) -> "Box"
            authority.contains("docs.google", ignoreCase = true) ||
                authority.contains("google", ignoreCase = true) ||
                authority.contains("drive", ignoreCase = true) -> "Google Drive"
            else -> null
        }
    }

    private fun saveInterval() {
        val interval = intervalInput.text.toString().toIntOrNull()?.coerceIn(1, 240) ?: 1
        prefs().edit().putInt(PREF_AUTO_INTERVAL, interval).apply()
        intervalInput.setText(interval.toString())
    }

    private fun prefs() = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    private fun showAbout() {
        AlertDialog.Builder(this)
            .setTitle("About Sync My Mobile")
            .setMessage(
                "Author: Bartholomew Diaz Michael\n\n" +
                    "Downloads selected Android phone folders to a Windows desktop over the same local network.\n" +
                    "The supporting desktop app discovers the phone, syncs files in parallel, and can run in the tray.",
            )
            .setPositiveButton("OK", null)
            .show()
    }

    private fun showCloudHelp() {
        AlertDialog.Builder(this)
            .setTitle("Cloud Access Help")
            .setMessage(
                "1. Install Google Drive, OneDrive, or Box and sign in.\n\n" +
                    "2. Tap Choose Source.\n\n" +
                    "3. Select Cloud Files.\n\n" +
                    "4. Android's file picker opens. Use the Open from side menu to choose Google Drive, OneDrive, or Box.\n\n" +
                    "5. Pick one or more files, then tap Select or Allow access.\n\n" +
                    "If a provider is missing, open that cloud app once, confirm you are signed in, and check the picker menu.",
            )
            .setPositiveButton("OK", null)
            .show()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }

    companion object {
        private const val REQUEST_TREE = 1001
        private const val REQUEST_FILES = 1003
        private const val REQUEST_NOTIFICATIONS = 1002
        private val CLOUD_PROVIDERS = listOf(
            CloudProvider("Google Drive", "com.google.android.apps.docs"),
            CloudProvider("OneDrive", "com.microsoft.skydrive"),
            CloudProvider("Box", "com.box.android"),
        )
    }
}

private data class CloudProvider(val name: String, val packageName: String)
private data class SafSelection(val providerName: String, val providerPackage: String?, val mode: CloudMode)
private enum class CloudMode {
    FOLDER,
    FILE,
}
