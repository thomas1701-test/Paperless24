package de.tedi.paperless.data.local

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class SecureTokenStore(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "paperless_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveToken(accountId: Long, token: String) {
        prefs.edit().putString("token_$accountId", token).apply()
    }

    fun getToken(accountId: Long): String? = prefs.getString("token_$accountId", null)

    fun removeToken(accountId: Long) {
        prefs.edit().remove("token_$accountId").apply()
    }

    fun saveCloudAiApiKey(key: String) { prefs.edit().putString("cloud_ai_api_key", key).apply() }
    fun getCloudAiApiKey(): String? = prefs.getString("cloud_ai_api_key", null)
}
