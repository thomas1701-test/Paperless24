package de.tedi.paperless.sync

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class InboxCheckWorkerTest {
    @Test
    fun `notifies when count increased`() {
        assertTrue(shouldNotify(count = 5, lastSeen = 2))
    }

    @Test
    fun `does not notify when count unchanged or decreased`() {
        assertFalse(shouldNotify(count = 3, lastSeen = 3))
        assertFalse(shouldNotify(count = 1, lastSeen = 3))
    }

    @Test
    fun `new document count is the difference`() {
        assertEquals(3, newDocumentCount(count = 5, lastSeen = 2))
    }

    @Test
    fun `new document count never negative`() {
        assertEquals(0, newDocumentCount(count = 1, lastSeen = 3))
        assertEquals(0, newDocumentCount(count = 3, lastSeen = 3))
    }
}
