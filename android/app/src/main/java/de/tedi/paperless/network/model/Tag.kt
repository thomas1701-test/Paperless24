package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Tag(val id: Int, val name: String, val colour: String? = null)
