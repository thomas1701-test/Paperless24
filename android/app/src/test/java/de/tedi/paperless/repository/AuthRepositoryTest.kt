package de.tedi.paperless.repository

import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.SecureTokenStore
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import kotlin.test.assertTrue

class AuthRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: AuthRepository
    private val accountDao: AccountDao = mock()
    private val tokenStore: SecureTokenStore = mock()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        repository = AuthRepository(accountDao, tokenStore)
    }

    @After
    fun tearDown() { server.shutdown() }

    @Test
    fun `login returns OtpRequired when server responds 401 with otp keyword`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401).setBody("""{"non_field_errors":["Please enter your OTP code."]}"""))

        val result = repository.login(server.url("/").toString(), "user", "pass")

        assertTrue(result is LoginResult.OtpRequired)
    }
}
