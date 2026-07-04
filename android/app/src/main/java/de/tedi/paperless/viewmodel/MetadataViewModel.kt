package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.network.model.Tag
import de.tedi.paperless.repository.MetadataRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MetadataState(val tags: List<Tag> = emptyList())

@HiltViewModel
class MetadataViewModel @Inject constructor(
    private val repository: MetadataRepository
) : ViewModel() {
    private val _state = MutableStateFlow(MetadataState())
    val state: StateFlow<MetadataState> = _state

    fun loadTags() {
        viewModelScope.launch {
            _state.update { it.copy(tags = repository.getTags()) }
        }
    }

    fun createTag(name: String) {
        viewModelScope.launch {
            val tag = repository.createTag(name)
            _state.update { it.copy(tags = it.tags + tag) }
        }
    }

    fun deleteTag(id: Int) {
        viewModelScope.launch {
            repository.deleteTag(id)
            _state.update { it.copy(tags = it.tags.filterNot { t -> t.id == id }) }
        }
    }
}
