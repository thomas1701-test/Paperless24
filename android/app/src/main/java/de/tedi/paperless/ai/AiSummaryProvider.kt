package de.tedi.paperless.ai

interface AiSummaryProvider {
    suspend fun isAvailable(): Boolean
    suspend fun summarize(text: String): String
    suspend fun suggestTags(text: String, existingTags: List<String>): List<String>
}
