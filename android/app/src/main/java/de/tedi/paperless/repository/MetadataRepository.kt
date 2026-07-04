package de.tedi.paperless.repository

import de.tedi.paperless.network.model.Correspondent
import de.tedi.paperless.network.model.DocumentType
import de.tedi.paperless.network.model.Tag
import javax.inject.Inject

class MetadataRepository @Inject constructor(
    private val serviceProvider: ServiceProvider
) {
    suspend fun getTags(): List<Tag> =
        (serviceProvider.current() ?: error("No active account")).getTags().results

    suspend fun createTag(name: String): Tag =
        (serviceProvider.current() ?: error("No active account")).createTag(mapOf("name" to name))

    suspend fun deleteTag(id: Int) {
        (serviceProvider.current() ?: error("No active account")).deleteTag(id)
    }

    suspend fun getCorrespondents(): List<Correspondent> =
        (serviceProvider.current() ?: error("No active account")).getCorrespondents().results

    suspend fun createCorrespondent(name: String): Correspondent =
        (serviceProvider.current() ?: error("No active account")).createCorrespondent(mapOf("name" to name))

    suspend fun deleteCorrespondent(id: Int) {
        (serviceProvider.current() ?: error("No active account")).deleteCorrespondent(id)
    }

    suspend fun getDocumentTypes(): List<DocumentType> =
        (serviceProvider.current() ?: error("No active account")).getDocumentTypes().results

    suspend fun createDocumentType(name: String): DocumentType =
        (serviceProvider.current() ?: error("No active account")).createDocumentType(mapOf("name" to name))

    suspend fun deleteDocumentType(id: Int) {
        (serviceProvider.current() ?: error("No active account")).deleteDocumentType(id)
    }
}
