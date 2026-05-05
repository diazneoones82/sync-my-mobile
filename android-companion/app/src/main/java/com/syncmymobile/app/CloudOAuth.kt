package com.syncmymobile.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom

enum class CloudProviderId {
    GOOGLE_DRIVE,
    ONEDRIVE,
    BOX,
}

data class OAuthProvider(
    val id: CloudProviderId,
    val displayName: String,
    val clientId: String,
    val authUrl: String,
    val tokenUrl: String,
    val scopes: String,
)

object CloudOAuth {
    private const val PREF_CODE_VERIFIER_PREFIX = "oauth-code-verifier-"
    private const val PREF_ACCESS_TOKEN_PREFIX = "oauth-access-token-"
    private const val PREF_REFRESH_TOKEN_PREFIX = "oauth-refresh-token-"

    fun providers(context: Context): List<OAuthProvider> {
        return listOf(
            OAuthProvider(
                id = CloudProviderId.GOOGLE_DRIVE,
                displayName = "Google Drive",
                clientId = context.getString(R.string.google_drive_client_id),
                authUrl = "https://accounts.google.com/o/oauth2/v2/auth",
                tokenUrl = "https://oauth2.googleapis.com/token",
                scopes = "https://www.googleapis.com/auth/drive.readonly",
            ),
            OAuthProvider(
                id = CloudProviderId.ONEDRIVE,
                displayName = "OneDrive",
                clientId = context.getString(R.string.onedrive_client_id),
                authUrl = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                tokenUrl = "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                scopes = "offline_access Files.Read.All",
            ),
            OAuthProvider(
                id = CloudProviderId.BOX,
                displayName = "Box",
                clientId = context.getString(R.string.box_client_id),
                authUrl = "https://account.box.com/api/oauth2/authorize",
                tokenUrl = "https://api.box.com/oauth2/token",
                scopes = "root_readonly",
            ),
        )
    }

    fun provider(context: Context, id: CloudProviderId): OAuthProvider {
        return providers(context).first { it.id == id }
    }

    fun isConfigured(provider: OAuthProvider): Boolean {
        return !provider.clientId.startsWith("REPLACE_WITH_")
    }

    fun authIntent(context: Context, provider: OAuthProvider): Intent {
        val verifier = randomVerifier()
        val challenge = codeChallenge(verifier)
        prefs(context).edit()
            .putString(PREF_CODE_VERIFIER_PREFIX + provider.id.name, verifier)
            .apply()

        val redirectUri = context.getString(R.string.oauth_redirect_uri)
        val uri = Uri.parse(provider.authUrl).buildUpon()
            .appendQueryParameter("client_id", provider.clientId)
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("scope", provider.scopes)
            .appendQueryParameter("state", provider.id.name)
            .appendQueryParameter("code_challenge", challenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()
        return Intent(Intent.ACTION_VIEW, uri)
    }

    fun exchangeCode(context: Context, provider: OAuthProvider, code: String): String {
        val verifier = prefs(context).getString(PREF_CODE_VERIFIER_PREFIX + provider.id.name, null)
            ?: error("Missing OAuth verifier")
        val redirectUri = context.getString(R.string.oauth_redirect_uri)
        val body = mapOf(
            "client_id" to provider.clientId,
            "redirect_uri" to redirectUri,
            "grant_type" to "authorization_code",
            "code" to code,
            "code_verifier" to verifier,
        ).formUrlEncoded()

        val json = postForm(provider.tokenUrl, body)
        val accessToken = json.getString("access_token")
        val refreshToken = json.optString("refresh_token", "")
        prefs(context).edit()
            .putString(PREF_ACCESS_TOKEN_PREFIX + provider.id.name, accessToken)
            .putString(PREF_REFRESH_TOKEN_PREFIX + provider.id.name, refreshToken)
            .apply()
        return accessToken
    }

    fun accessToken(context: Context, id: CloudProviderId): String? {
        return prefs(context).getString(PREF_ACCESS_TOKEN_PREFIX + id.name, null)
    }

    private fun postForm(url: String, body: String): JSONObject {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        OutputStreamWriter(connection.outputStream).use { it.write(body) }
        val stream = if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream
        val response = stream.bufferedReader().use { it.readText() }
        if (connection.responseCode !in 200..299) error(response)
        return JSONObject(response)
    }

    private fun randomVerifier(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun codeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
        return Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    private fun Map<String, String>.formUrlEncoded(): String {
        return entries.joinToString("&") {
            "${URLEncoder.encode(it.key, "UTF-8")}=${URLEncoder.encode(it.value, "UTF-8")}"
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
