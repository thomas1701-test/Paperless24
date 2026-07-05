package de.tedi.paperless.ui.documents

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.DocumentDetailViewModel

@Composable
fun DocumentDetailScreen(
    documentId: Int,
    viewModel: DocumentDetailViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(documentId) { viewModel.load(documentId) }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        if (state.isLoading) {
            CircularProgressIndicator()
        }
        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        state.document?.let { doc ->
            Text(doc.title, style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            Text("Erstellt: ${doc.created}")
            Spacer(Modifier.height(8.dp))
            Text("Tags: ${doc.tags.joinToString(", ")}")
            Spacer(Modifier.height(8.dp))
            Button(
                onClick = { viewModel.translate() },
                enabled = !doc.content.isNullOrBlank() && !state.isTranslating
            ) {
                Text("Übersetzen")
            }
            if (state.isTranslating) {
                Spacer(Modifier.height(8.dp))
                CircularProgressIndicator()
            }
            state.translatedText?.let {
                Spacer(Modifier.height(8.dp))
                Text(it)
            }
            state.translationError?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = MaterialTheme.colorScheme.error)
            }
        }
        state.pdfFile?.let { file -> PdfViewer(file) }
    }
}
