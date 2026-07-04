package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.repository.AuthRepository
import de.tedi.paperless.repository.LoginResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class LoginUiState {
    object Idle : LoginUiState()
    object Loading : LoginUiState()
    object OtpNeeded : LoginUiState()
    data class LoggedIn(val accountId: Long) : LoginUiState()
    data class Error(val message: String) : LoginUiState()
}

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {
    private val _state = MutableStateFlow<LoginUiState>(LoginUiState.Idle)
    val state: StateFlow<LoginUiState> = _state

    fun login(serverUrl: String, username: String, password: String, otp: String? = null) {
        viewModelScope.launch {
            _state.value = LoginUiState.Loading
            when (val result = authRepository.login(serverUrl, username, password, otp)) {
                is LoginResult.Success -> _state.value = LoginUiState.LoggedIn(result.accountId)
                is LoginResult.OtpRequired -> _state.value = LoginUiState.OtpNeeded
                is LoginResult.Failure -> _state.value = LoginUiState.Error(result.message)
            }
        }
    }
}
