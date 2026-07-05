package de.tedi.paperless

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.core.app.ActivityCompat
import androidx.fragment.app.FragmentActivity
import dagger.hilt.android.AndroidEntryPoint
import de.tedi.paperless.sync.SyncScheduler
import de.tedi.paperless.ui.PaperlessNavHost
import de.tedi.paperless.ui.auth.BiometricGate

@AndroidEntryPoint
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestNotificationPermissionIfNeeded()
        SyncScheduler.schedule(applicationContext)

        // Launched from the home screen widget (PaperlessWidget) when the user taps a document.
        // Deep-link routing straight to DocumentDetailScreen on cold start is out of scope for
        // Task 14; this is only read/logged for now.
        val widgetDocumentId = intent.getIntExtra("documentId", -1)
        if (widgetDocumentId != -1) {
            Log.d("MainActivity", "Launched from widget for documentId=$widgetDocumentId")
        }

        setContent {
            BiometricGate(enabled = false) {
                PaperlessNavHost()
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_CODE_NOTIFICATIONS
            )
        }
    }

    companion object {
        private const val REQUEST_CODE_NOTIFICATIONS = 1
    }
}
