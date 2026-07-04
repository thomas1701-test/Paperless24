package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class DocumentType(val id: Int, val name: String)
