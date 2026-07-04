package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class UploadUiState {
    object Idle : UploadUiState()
    object Uploading : UploadUiState()
    object Success : UploadUiState()
    data class Error(val message: String) : UploadUiState()
}

@HiltViewModel
class UploadViewModel @Inject constructor(
    private val repository: DocumentRepository
) : ViewModel() {
    private val _state = MutableStateFlow<UploadUiState>(UploadUiState.Idle)
    val state: StateFlow<UploadUiState> = _state

    fun upload(bytes: ByteArray, filename: String) {
        viewModelScope.launch {
            _state.value = UploadUiState.Uploading
            _state.value = try {
                repository.uploadFile(bytes, filename)
                UploadUiState.Success
            } catch (e: Exception) {
                UploadUiState.Error(e.message ?: "Upload fehlgeschlagen")
            }
        }
    }
}
