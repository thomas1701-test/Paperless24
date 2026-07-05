package de.tedi.paperless.search

import de.tedi.paperless.network.model.Document
import org.junit.Test
import kotlin.test.assertEquals

class SemanticSearchRepositoryTest {
    @Test
    fun `ranks documents by keyword overlap with query descending`() {
        val docs = listOf(
            Document(id = 1, title = "Stromrechnung", content = "Jahresabrechnung Energie", created = "2026-01-01"),
            Document(id = 2, title = "Mietvertrag", content = "Wohnung Miete Kaution", created = "2026-01-01"),
            Document(id = 3, title = "Stromvertrag Energie", content = "Energie Anbieter Strom", created = "2026-01-01")
        )

        val ranked = rankByOverlap("Strom Energie Rechnung", docs)

        assertEquals(listOf(3, 1), ranked.map { it.id }.filter { it == 3 || it == 1 })
        assertEquals(2, ranked.size)
    }
}
