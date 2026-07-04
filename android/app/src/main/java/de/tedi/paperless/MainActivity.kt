package de.tedi.paperless

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.fragment.app.FragmentActivity
import dagger.hilt.android.AndroidEntryPoint
import de.tedi.paperless.ui.PaperlessNavHost
import de.tedi.paperless.ui.auth.BiometricGate

@AndroidEntryPoint
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BiometricGate(enabled = false) {
                PaperlessNavHost()
            }
        }
    }
}
