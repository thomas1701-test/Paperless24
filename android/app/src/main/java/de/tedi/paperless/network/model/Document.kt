package de.tedi.paperless.network.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Document(
    val id: Int,
    val title: String,
    val content: String? = null,
    val created: String,
    val added: String? = null,
    val correspondent: Int? = null,
    @Json(name = "document_type") val documentType: Int? = null,
    @Json(name = "archive_serial_number") val archiveSerialNumber: Int? = null,
    val tags: List<Int> = emptyList()
)
