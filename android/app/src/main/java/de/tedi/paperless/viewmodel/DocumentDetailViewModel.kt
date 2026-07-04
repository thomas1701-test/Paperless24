package de.tedi.paperless.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class DocumentDetailState(
    val document: Document? = null,
    val pdfFile: File? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class DocumentDetailViewModel @Inject constructor(
    private val repository: DocumentRepository,
    @ApplicationContext private val context: Context
) : ViewModel() {
    private val _state = MutableStateFlow(DocumentDetailState())
    val state: StateFlow<DocumentDetailState> = _state

    fun load(id: Int) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val doc = repository.getDocument(id)
                val pdfBody = repository.downloadDocument(id)
                val file = File(context.cacheDir, "doc_$id.pdf")
                file.outputStream().use { out -> pdfBody.byteStream().copyTo(out) }
                _state.update { it.copy(document = doc, pdfFile = file, isLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }
}
