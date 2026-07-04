package de.tedi.paperless.ui.upload

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.UploadUiState
import de.tedi.paperless.viewmodel.UploadViewModel

@Composable
fun UploadScreen(viewModel: UploadViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            val bytes = context.contentResolver.openInputStream(uri)?.use { s -> s.readBytes() }
            if (bytes != null) {
                viewModel.upload(bytes, "upload_${System.currentTimeMillis()}.pdf")
            }
        }
    }

    val scanLauncher = rememberScannerLauncher { result ->
        val uri = result.pdf?.uri
        if (uri != null) {
            val bytes = context.contentResolver.openInputStream(uri)?.use { s -> s.readBytes() }
            if (bytes != null) {
                viewModel.upload(bytes, "scan_${System.currentTimeMillis()}.pdf")
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Button(onClick = scanLauncher, modifier = Modifier.fillMaxWidth()) { Text("Dokument scannen") }
        Spacer(Modifier.height(8.dp))
        Button(onClick = { filePicker.launch("application/pdf") }, modifier = Modifier.fillMaxWidth()) {
            Text("Datei auswählen")
        }
        Spacer(Modifier.height(16.dp))
        when (state) {
            is UploadUiState.Uploading -> CircularProgressIndicator()
            is UploadUiState.Success -> Text("Upload erfolgreich")
            is UploadUiState.Error -> Text((state as UploadUiState.Error).message, color = MaterialTheme.colorScheme.error)
            else -> {}
        }
    }
}
