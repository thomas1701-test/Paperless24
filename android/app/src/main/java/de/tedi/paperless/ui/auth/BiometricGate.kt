package de.tedi.paperless.ui.auth

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

@Composable
fun BiometricGate(enabled: Boolean, content: @Composable () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var unlocked by remember { mutableStateOf(!enabled) }

    LaunchedEffect(enabled) {
        if (!enabled) return@LaunchedEffect
        val activity = context as FragmentActivity
        val manager = BiometricManager.from(context)
        val canAuth = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            unlocked = true
            return@LaunchedEffect
        }
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(context),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    unlocked = true
                }
            }
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Paperless TeDi entsperren")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            .setNegativeButtonText("Abbrechen")
            .build()
        prompt.authenticate(info)
    }

    if (unlocked) content() else CircularProgressIndicator()
}
