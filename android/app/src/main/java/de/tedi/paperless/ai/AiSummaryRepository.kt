package de.tedi.paperless.ai

import javax.inject.Inject
import javax.inject.Named

class AiSummaryRepository @Inject constructor(
    @Named("onDevice") private val onDeviceProvider: AiSummaryProvider,
    @Named("cloud") private val cloudProvider: AiSummaryProvider
) {
    private suspend fun activeProvider(): AiSummaryProvider =
        if (onDeviceProvider.isAvailable()) onDeviceProvider else cloudProvider

    suspend fun summarize(text: String): String = activeProvider().summarize(text)

    suspend fun suggestTags(text: String, existingTags: List<String>): List<String> =
        activeProvider().suggestTags(text, existingTags)

    suspend fun answer(question: String, context: List<String>): String =
        activeProvider().answer(question, context)
}
