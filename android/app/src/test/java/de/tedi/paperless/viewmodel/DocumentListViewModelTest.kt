package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.network.model.PagedResponse
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class DocumentListViewModelTest {
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUpDispatcher() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDownDispatcher() {
        Dispatchers.resetMain()
    }

    @Test
    fun `loadFirstPage populates documents from repository`() = runTest {
        val repo: DocumentRepository = mock()
        val doc = Document(id = 1, title = "Rechnung", created = "2026-01-01T00:00:00Z")
        whenever(repo.getDocuments(1, 25)).thenReturn(PagedResponse(1, null, null, listOf(doc)))
        val vm = DocumentListViewModel(repo)

        vm.state.test {
            assertEquals(emptyList(), awaitItem().documents)
            vm.loadFirstPage()
            awaitItem() // isLoading = true
            assertEquals(listOf(doc), awaitItem().documents)
        }
    }
}
