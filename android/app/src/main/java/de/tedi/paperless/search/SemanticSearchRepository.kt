package de.tedi.paperless.search

import de.tedi.paperless.ai.AiSummaryRepository
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import javax.inject.Inject

/**
 * There is no zero-setup Android equivalent to Apple's NLEmbedding, and adding a heavy on-device
 * embedding model is out of scope for this phase. Instead, retrieval is done with simple
 * keyword/term-overlap scoring over the already-fetched working set of documents, and the final
 * natural-language answer is composed by [AiSummaryRepository] from the top-ranked documents.
 */
class SemanticSearchRepository @Inject constructor(
    private val documentRepository: DocumentRepository,
    private val aiSummaryRepository: AiSummaryRepository
) {
    suspend fun ask(question: String): String {
        val allDocs = documentRepository.getDocuments(page = 1, pageSize = 200).results
        val ranked = rankByOverlap(question, allDocs).take(5)
        val context = ranked.map { "${it.title}: ${it.content.orEmpty()}" }
        return aiSummaryRepository.answer(question, context)
    }
}

fun rankByOverlap(query: String, documents: List<Document>): List<Document> {
    fun tokenize(s: String) = s.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotBlank() }.toSet()
    val queryTokens = tokenize(query)
    return documents
        .map { doc -> doc to tokenize("${doc.title} ${doc.content.orEmpty()}").intersect(queryTokens).size }
        .filter { it.second > 0 }
        .sortedByDescending { it.second }
        .map { it.first }
}
