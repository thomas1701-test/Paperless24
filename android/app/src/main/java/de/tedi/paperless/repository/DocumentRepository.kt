package de.tedi.paperless.repository

import de.tedi.paperless.network.model.Document
import de.tedi.paperless.network.model.PagedResponse
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
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

    suspend fun downloadDocument(id: Int): okhttp3.ResponseBody {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.downloadDocument(id).body() ?: throw IllegalStateException("Empty PDF body")
    }

    suspend fun uploadFile(fileBytes: ByteArray, filename: String): Boolean {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        val requestBody = fileBytes.toRequestBody("application/octet-stream".toMediaTypeOrNull())
        val part = okhttp3.MultipartBody.Part.createFormData("document", filename, requestBody)
        return service.uploadDocument(part).isSuccessful
    }
}
