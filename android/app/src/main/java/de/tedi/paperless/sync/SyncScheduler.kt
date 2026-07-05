package de.tedi.paperless.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules the periodic [InboxCheckWorker] that checks for new documents and notifies the user.
 */
object SyncScheduler {
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<InboxCheckWorker>(1, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "inbox_check", ExistingPeriodicWorkPolicy.KEEP, request
        )
    }
}
