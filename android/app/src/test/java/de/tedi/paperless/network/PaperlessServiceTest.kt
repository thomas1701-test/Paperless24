package de.tedi.paperless.network

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals

class PaperlessServiceTest {
    private lateinit var server: MockWebServer
    private lateinit var service: PaperlessService

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        service = RetrofitFactory.create(server.url("/").toString(), "test-token")
    }

    @After
    fun tearDown() { server.shutdown() }

    @Test
    fun `getDocuments parses paged response and sends auth header`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"count":1,"next":null,"previous":null,"results":[
                    {"id":1,"title":"Rechnung","created":"2026-01-01T00:00:00Z","tags":[1,2]}
                ]}"""
            ).setResponseCode(200)
        )

        val page = service.getDocuments(page = 1, pageSize = 25)

        assertEquals(1, page.results.size)
        assertEquals("Rechnung", page.results[0].title)
        val recorded = server.takeRequest()
        assertEquals("Token test-token", recorded.getHeader("Authorization"))
    }
}
