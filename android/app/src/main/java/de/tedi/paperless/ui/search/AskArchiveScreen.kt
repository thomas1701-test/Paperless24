package de.tedi.paperless.ui.search

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.AskArchiveViewModel

@Composable
fun AskArchiveScreen(
    viewModel: AskArchiveViewModel = hiltViewModel()
) {
    var question by remember { mutableStateOf("") }
    val state by viewModel.state.collectAsState()

    Column(modifier = Modifier.padding(24.dp).fillMaxSize()) {
        Text("Archiv fragen", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = question,
            onValueChange = { question = it },
            label = { Text("Deine Frage") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = { viewModel.ask(question) },
            enabled = !state.isLoading && question.isNotBlank(),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (state.isLoading) "Suche läuft…" else "Fragen")
        }
        Spacer(Modifier.height(24.dp))
        if (state.isLoading) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        if (state.error != null) {
            Text(state.error!!, color = MaterialTheme.colorScheme.error)
        }
        if (state.answer != null) {
            Text(state.answer!!, style = MaterialTheme.typography.bodyLarge)
        }
    }
}
