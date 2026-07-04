package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.repository.AuthRepository
import de.tedi.paperless.repository.LoginResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertTrue

class LoginViewModelTest {
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
    fun `successful login updates state to LoggedIn`() = runTest {
        val repo: AuthRepository = mock()
        whenever(repo.login("https://s", "u", "p", null)).thenReturn(LoginResult.Success(1L))
        val vm = LoginViewModel(repo)

        vm.state.test {
            assertTrue(awaitItem() is LoginUiState.Idle)
            vm.login("https://s", "u", "p")
            assertTrue(awaitItem() is LoginUiState.Loading)
            assertTrue(awaitItem() is LoginUiState.LoggedIn)
        }
    }

    @Test
    fun `otp required shows OtpNeeded state`() = runTest {
        val repo: AuthRepository = mock()
        whenever(repo.login("https://s", "u", "p", null)).thenReturn(LoginResult.OtpRequired)
        val vm = LoginViewModel(repo)

        vm.state.test {
            awaitItem()
            vm.login("https://s", "u", "p")
            awaitItem()
            assertTrue(awaitItem() is LoginUiState.OtpNeeded)
        }
    }
}
