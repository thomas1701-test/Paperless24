package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Correspondent(val id: Int, val name: String)
