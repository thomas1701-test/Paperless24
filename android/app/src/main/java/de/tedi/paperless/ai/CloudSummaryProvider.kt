package de.tedi.paperless.ai

import de.tedi.paperless.data.local.SecureTokenStore
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import javax.inject.Inject

class CloudSummaryProvider @Inject constructor(
    private val secureTokenStore: SecureTokenStore
) : AiSummaryProvider {
    private val client = OkHttpClient()

    private fun apiKey(): String? = secureTokenStore.getCloudAiApiKey()

    override suspend fun isAvailable(): Boolean = !apiKey().isNullOrBlank()

    private fun callClaude(prompt: String): String {
        val key = apiKey() ?: throw IllegalStateException("Kein API-Key hinterlegt")
        val body = JSONObject().apply {
            put("model", "claude-sonnet-5")
            put("max_tokens", 512)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", prompt)
            }))
        }.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("https://api.anthropic.com/v1/messages")
            .addHeader("x-api-key", key)
            .addHeader("anthropic-version", "2023-06-01")
            .post(body)
            .build()

        client.newCall(request).execute().use { response ->
            val json = JSONObject(response.body?.string() ?: "{}")
            return json.optJSONArray("content")?.optJSONObject(0)?.optString("text") ?: ""
        }
    }

    override suspend fun summarize(text: String): String =
        callClaude("Fasse folgenden Text in 1-3 Sätzen zusammen:\n$text")

    override suspend fun suggestTags(text: String, existingTags: List<String>): List<String> {
        val result = callClaude("Schlage passende Tags aus dieser Liste vor: ${existingTags.joinToString(", ")}\nText: $text\nAntworte nur mit einer kommagetrennten Liste.")
        return result.split(",").map { it.trim() }.filter { it.isNotBlank() }
    }

    override suspend fun answer(question: String, context: List<String>): String {
        val prompt = "Beantworte die folgende Frage anhand der gegebenen Dokumente. " +
            "Frage: $question\n\nDokumente:\n${context.joinToString("\n---\n")}"
        return callClaude(prompt)
    }
}
