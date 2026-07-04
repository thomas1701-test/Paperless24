package de.tedi.paperless.repository

import de.tedi.paperless.network.model.Document
import de.tedi.paperless.network.model.PagedResponse
import javax.inject.Inject

class DocumentRepository @Inject constructor(
    private val serviceProvider: ServiceProvider
) {
    suspend fun getDocuments(page: Int, pageSize: Int = 25): PagedResponse<Document> {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.getDocuments(page = page, pageSize = pageSize)
    }

    suspend fun search(query: String, page: Int = 1, pageSize: Int = 25): PagedResponse<Document> {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.searchDocuments(query = query, page = page, pageSize = pageSize)
    }

    suspend fun getDocument(id: Int): Document {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.getDocument(id)
    }
}
