package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertTrue

class UploadViewModelTest {
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `upload success sets Success state`() = runTest {
        val repo: DocumentRepository = mock()
        whenever(repo.uploadFile(any(), any())).thenReturn(true)
        val vm = UploadViewModel(repo)

        vm.state.test {
            assertTrue(awaitItem() is UploadUiState.Idle)
            vm.upload(byteArrayOf(1, 2, 3), "scan.pdf")
            assertTrue(awaitItem() is UploadUiState.Uploading)
            assertTrue(awaitItem() is UploadUiState.Success)
        }
    }
}
