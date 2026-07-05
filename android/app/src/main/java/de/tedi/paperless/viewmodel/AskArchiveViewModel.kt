package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.search.SemanticSearchRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AskArchiveState(
    val question: String = "",
    val answer: String? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class AskArchiveViewModel @Inject constructor(
    private val semanticSearchRepository: SemanticSearchRepository
) : ViewModel() {
    private val _state = MutableStateFlow(AskArchiveState())
    val state: StateFlow<AskArchiveState> = _state

    fun ask(question: String) {
        viewModelScope.launch {
            _state.update { it.copy(question = question, isLoading = true, error = null) }
            try {
                val answer = semanticSearchRepository.ask(question)
                _state.update { it.copy(answer = answer, isLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }
}
