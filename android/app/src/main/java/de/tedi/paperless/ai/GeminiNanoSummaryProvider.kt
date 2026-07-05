package de.tedi.paperless.ai

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject

// Stub: the on-device Gemini Nano SDK (com.google.ai.edge.aicore:aicore:0.0.1-exp01) declares
// minSdk 31, which is incompatible with this app's minSdk 26. Raising minSdk or force-overriding
// the manifest check are both out of scope here, so this provider always reports unavailable and
// defers to CloudSummaryProvider via AiSummaryRepository's fallback logic. Replace this stub with
// a real GenerativeModel-backed implementation once the SDK supports minSdk 26 (or the app's
// minSdk is raised to 31+).
class GeminiNanoSummaryProvider @Inject constructor(
    @param:ApplicationContext private val context: Context
) : AiSummaryProvider {
    override suspend fun isAvailable(): Boolean = false

    override suspend fun summarize(text: String): String {
        throw UnsupportedOperationException("Gemini Nano ist auf diesem Gerät nicht verfügbar")
    }

    override suspend fun suggestTags(text: String, existingTags: List<String>): List<String> {
        throw UnsupportedOperationException("Gemini Nano ist auf diesem Gerät nicht verfügbar")
    }
}
