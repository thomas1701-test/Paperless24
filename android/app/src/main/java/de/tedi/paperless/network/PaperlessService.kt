package de.tedi.paperless.network

import de.tedi.paperless.network.model.Correspondent
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.network.model.DocumentType
import de.tedi.paperless.network.model.PagedResponse
import de.tedi.paperless.network.model.Tag
import okhttp3.MultipartBody
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming

data class TokenRequest(val username: String, val password: String, val code: String? = null)
data class TokenResponse(val token: String)

interface PaperlessService {
    @POST("api/token/")
    suspend fun fetchToken(@Body request: TokenRequest): TokenResponse

    @GET("api/documents/")
    suspend fun getDocuments(
        @Query("page") page: Int,
        @Query("page_size") pageSize: Int,
        @Query("ordering") ordering: String = "-created"
    ): PagedResponse<Document>

    @GET("api/documents/")
    suspend fun searchDocuments(
        @Query("query") query: String,
        @Query("page") page: Int,
        @Query("page_size") pageSize: Int
    ): PagedResponse<Document>

    @GET("api/documents/{id}/")
    suspend fun getDocument(@Path("id") id: Int): Document

    @GET("api/documents/{id}/download/")
    @Streaming
    suspend fun downloadDocument(@Path("id") id: Int): retrofit2.Response<okhttp3.ResponseBody>

    @GET("api/tags/")
    suspend fun getTags(@Query("page_size") pageSize: Int = 100): PagedResponse<Tag>

    @GET("api/correspondents/")
    suspend fun getCorrespondents(@Query("page_size") pageSize: Int = 100): PagedResponse<Correspondent>

    @GET("api/document_types/")
    suspend fun getDocumentTypes(@Query("page_size") pageSize: Int = 100): PagedResponse<DocumentType>

    @Multipart
    @POST("api/documents/post_document/")
    suspend fun uploadDocument(@Part file: MultipartBody.Part): retrofit2.Response<Unit>

    @POST("api/tags/")
    suspend fun createTag(@Body body: Map<String, String>): Tag

    @PATCH("api/tags/{id}/")
    suspend fun updateTag(@Path("id") id: Int, @Body body: Map<String, String>): Tag

    @DELETE("api/tags/{id}/")
    suspend fun deleteTag(@Path("id") id: Int): retrofit2.Response<Unit>

    @POST("api/correspondents/")
    suspend fun createCorrespondent(@Body body: Map<String, String>): Correspondent

    @DELETE("api/correspondents/{id}/")
    suspend fun deleteCorrespondent(@Path("id") id: Int): retrofit2.Response<Unit>

    @POST("api/document_types/")
    suspend fun createDocumentType(@Body body: Map<String, String>): DocumentType

    @DELETE("api/document_types/{id}/")
    suspend fun deleteDocumentType(@Path("id") id: Int): retrofit2.Response<Unit>
}
