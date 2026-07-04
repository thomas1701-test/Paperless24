package de.tedi.paperless.viewmodel

import androidx.test.core.app.ApplicationProvider
import app.cash.turbine.test
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class DocumentDetailViewModelTest {
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUpDispatcher() { Dispatchers.setMain(testDispatcher) }

    @After
    fun tearDownDispatcher() { Dispatchers.resetMain() }

    @Test
    fun `load fetches document by id`() = runTest {
        val repo: DocumentRepository = mock()
        val doc = Document(id = 42, title = "Vertrag", created = "2026-01-01T00:00:00Z")
        whenever(repo.getDocument(42)).thenReturn(doc)
        whenever(repo.downloadDocument(42)).thenReturn(ByteArray(0).toResponseBody(null))
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val vm = DocumentDetailViewModel(repo, context)

        vm.state.test {
            assertEquals(null, awaitItem().document)
            vm.load(42)
            awaitItem() // intermediate isLoading=true emission
            assertEquals(doc, awaitItem().document)
        }
    }
}
