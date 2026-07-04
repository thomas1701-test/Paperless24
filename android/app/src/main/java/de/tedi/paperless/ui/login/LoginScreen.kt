package de.tedi.paperless.ui.login

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.LoginUiState
import de.tedi.paperless.viewmodel.LoginViewModel

@Composable
fun LoginScreen(
    onLoggedIn: (Long) -> Unit,
    viewModel: LoginViewModel = hiltViewModel()
) {
    var serverUrl by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var otp by remember { mutableStateOf("") }
    val state by viewModel.state.collectAsState()

    LaunchedEffect(state) {
        if (state is LoginUiState.LoggedIn) onLoggedIn((state as LoginUiState.LoggedIn).accountId)
    }

    Column(modifier = Modifier.padding(24.dp).fillMaxSize(), verticalArrangement = Arrangement.Center) {
        Text("Paperless TeDi", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(value = serverUrl, onValueChange = { serverUrl = it }, label = { Text("Server-URL") }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(value = username, onValueChange = { username = it }, label = { Text("Benutzername") }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text("Passwort") }, modifier = Modifier.fillMaxWidth())
        if (state is LoginUiState.OtpNeeded) {
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(value = otp, onValueChange = { otp = it }, label = { Text("2FA-Code") }, modifier = Modifier.fillMaxWidth())
        }
        if (state is LoginUiState.Error) {
            Spacer(Modifier.height(8.dp))
            Text((state as LoginUiState.Error).message, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = { viewModel.login(serverUrl, username, password, otp.ifBlank { null }) },
            enabled = state !is LoginUiState.Loading,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (state is LoginUiState.Loading) "Anmeldung läuft…" else "Anmelden")
        }
    }
}
