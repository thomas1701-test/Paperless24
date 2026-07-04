package de.tedi.paperless.data.local

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertEquals
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
class AccountDaoTest {
    private lateinit var db: AppDatabase
    private lateinit var dao: AccountDao

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.accountDao()
    }

    @After
    fun tearDown() { db.close() }

    @Test
    fun `setActive marks only one account active`() = runTest {
        val id1 = dao.insert(AccountEntity(serverUrl = "https://a.example", username = "u1"))
        val id2 = dao.insert(AccountEntity(serverUrl = "https://b.example", username = "u2"))

        dao.clearActive()
        dao.setActive(id2)

        val active = dao.getActive()
        assertEquals(id2, active?.id)
    }

    @Test
    fun `getActive returns null when no account is active`() = runTest {
        dao.insert(AccountEntity(serverUrl = "https://a.example", username = "u1"))
        assertNull(dao.getActive())
    }
}
