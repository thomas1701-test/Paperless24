package de.tedi.paperless.ui.documents

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.viewmodel.DocumentListViewModel

@Composable
fun DocumentListScreen(
    onDocumentClick: (Int) -> Unit,
    viewModel: DocumentListViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) { viewModel.loadFirstPage() }

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            label = { Text("Suche") },
            trailingIcon = {
                IconButton(onClick = { viewModel.search(query) }) {
                    Icon(Icons.Default.Search, contentDescription = "Suchen")
                }
            },
            modifier = Modifier.fillMaxWidth().padding(16.dp)
        )
        if (state.error != null) {
            Text(state.error!!, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp))
        }
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(state.documents, key = { it.id }) { doc: Document ->
                ListItem(
                    headlineContent = { Text(doc.title) },
                    supportingContent = { Text(doc.created) },
                    modifier = Modifier.clickable { onDocumentClick(doc.id) }
                )
                HorizontalDivider()
            }
            if (state.hasNext) {
                item {
                    LaunchedEffect(Unit) { viewModel.loadNextPage() }
                    Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
            }
        }
    }
}
