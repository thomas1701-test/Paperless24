package de.tedi.paperless.sync

import android.content.Context
import android.content.SharedPreferences
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import de.tedi.paperless.repository.DocumentRepository

private const val PREFS_NAME = "sync_prefs"
private const val KEY_LAST_SEEN_COUNT = "last_seen_count"

/**
 * Returns whether a notification should be shown for the current inbox [count] given the
 * [lastSeen] count from the previous check.
 */
fun shouldNotify(count: Int, lastSeen: Int): Boolean = count > lastSeen

/**
 * Returns how many new documents appeared since the last check. Never negative.
 */
fun newDocumentCount(count: Int, lastSeen: Int): Int = (count - lastSeen).coerceAtLeast(0)

/**
 * Periodic background worker that checks the Paperless inbox document count and posts a
 * notification when new documents have arrived since the last check.
 */
@HiltWorker
class InboxCheckWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val documentRepository: DocumentRepository
) : CoroutineWorker(context, params) {

    private val prefs: SharedPreferences
        get() = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override suspend fun doWork(): Result {
        return try {
            val lastSeenCount = prefs.getInt(KEY_LAST_SEEN_COUNT, 0)
            val count = documentRepository.getDocuments(page = 1, pageSize = 1).count

            if (shouldNotify(count, lastSeenCount)) {
                NotificationHelper.postInboxNotification(
                    applicationContext,
                    newDocumentCount(count, lastSeenCount)
                )
            }

            prefs.edit().putInt(KEY_LAST_SEEN_COUNT, count).apply()

            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }
}
