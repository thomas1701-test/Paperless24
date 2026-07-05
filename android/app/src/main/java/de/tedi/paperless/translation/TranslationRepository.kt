package de.tedi.paperless.translation

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.tasks.await
import java.util.Locale
import javax.inject.Inject

class TranslationRepository @Inject constructor() {
    suspend fun translate(text: String, targetLanguageTag: String = Locale.getDefault().language): String {
        val targetLanguage = TranslateLanguage.fromLanguageTag(targetLanguageTag) ?: TranslateLanguage.GERMAN
        val options = TranslatorOptions.Builder()
            .setSourceLanguage(TranslateLanguage.GERMAN)
            .setTargetLanguage(targetLanguage)
            .build()
        val translator = Translation.getClient(options)
        try {
            val conditions = DownloadConditions.Builder().requireWifi().build()
            translator.downloadModelIfNeeded(conditions).await()
            return translator.translate(text).await()
        } finally {
            translator.close()
        }
    }
}
