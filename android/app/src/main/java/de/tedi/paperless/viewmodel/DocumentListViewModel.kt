package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DocumentListState(
    val documents: List<Document> = emptyList(),
    val isLoading: Boolean = false,
    val hasNext: Boolean = false,
    val error: String? = null,
    val page: Int = 1
)

@HiltViewModel
class DocumentListViewModel @Inject constructor(
    private val repository: DocumentRepository
) : ViewModel() {
    private val _state = MutableStateFlow(DocumentListState())
    val state: StateFlow<DocumentListState> = _state

    fun loadFirstPage() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val result = repository.getDocuments(page = 1)
                _state.update {
                    it.copy(documents = result.results, hasNext = result.next != null, page = 1, isLoading = false)
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun loadNextPage() {
        val current = _state.value
        if (!current.hasNext || current.isLoading) return
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            try {
                val nextPage = current.page + 1
                val result = repository.getDocuments(page = nextPage)
                _state.update {
                    it.copy(
                        documents = it.documents + result.results,
                        hasNext = result.next != null,
                        page = nextPage,
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun search(query: String) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val result = repository.search(query)
                _state.update {
                    it.copy(documents = result.results, hasNext = result.next != null, page = 1, isLoading = false)
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }
}
