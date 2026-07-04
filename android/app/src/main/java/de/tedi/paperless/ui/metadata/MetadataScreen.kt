package de.tedi.paperless.ui.metadata

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.MetadataViewModel

@Composable
fun MetadataScreen(viewModel: MetadataViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    var showDialog by remember { mutableStateOf(false) }
    var newTagName by remember { mutableStateOf("") }

    LaunchedEffect(Unit) { viewModel.loadTags() }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(onClick = { showDialog = true }) {
                Icon(Icons.Default.Add, contentDescription = "Tag hinzufügen")
            }
        }
    ) { padding ->
        LazyColumn(Modifier.padding(padding)) {
            items(state.tags, key = { it.id }) { tag ->
                ListItem(
                    headlineContent = { Text(tag.name) },
                    trailingContent = {
                        IconButton(onClick = { viewModel.deleteTag(tag.id) }) {
                            Icon(Icons.Default.Delete, contentDescription = "Löschen")
                        }
                    }
                )
            }
        }
        if (showDialog) {
            AlertDialog(
                onDismissRequest = { showDialog = false },
                confirmButton = {
                    TextButton(onClick = {
                        viewModel.createTag(newTagName)
                        newTagName = ""
                        showDialog = false
                    }) { Text("Hinzufügen") }
                },
                dismissButton = { TextButton(onClick = { showDialog = false }) { Text("Abbrechen") } },
                title = { Text("Neuer Tag") },
                text = { OutlinedTextField(value = newTagName, onValueChange = { newTagName = it }, label = { Text("Name") }) }
            )
        }
    }
}
