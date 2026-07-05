package de.tedi.paperless.ai

import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

class AiSummaryRepositoryTest {
    @Test
    fun `falls back to cloud provider when on-device is unavailable`() = runTest {
        val onDevice: AiSummaryProvider = mock()
        val cloud: AiSummaryProvider = mock()
        whenever(onDevice.isAvailable()).thenReturn(false)
        whenever(cloud.isAvailable()).thenReturn(true)
        whenever(cloud.summarize("text")).thenReturn("cloud summary")

        val repository = AiSummaryRepository(onDevice, cloud)

        assertEquals("cloud summary", repository.summarize("text"))
    }

    @Test
    fun `uses on-device provider when available`() = runTest {
        val onDevice: AiSummaryProvider = mock()
        val cloud: AiSummaryProvider = mock()
        whenever(onDevice.isAvailable()).thenReturn(true)
        whenever(onDevice.summarize("text")).thenReturn("on-device summary")

        val repository = AiSummaryRepository(onDevice, cloud)

        assertEquals("on-device summary", repository.summarize("text"))
    }
}
