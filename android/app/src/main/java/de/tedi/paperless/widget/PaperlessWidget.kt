package de.tedi.paperless.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import de.tedi.paperless.MainActivity
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository

@EntryPoint
@InstallIn(SingletonComponent::class)
interface WidgetEntryPoint {
    fun documentRepository(): DocumentRepository
}

// Delivered as an Intent extra of the same name ("documentId") on the MainActivity launched
// via actionStartActivity.
val documentIdKey = ActionParameters.Key<Int>("documentId")

class PaperlessWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val documents: List<Document>? = try {
            val entryPoint = EntryPointAccessors.fromApplication(
                context.applicationContext,
                WidgetEntryPoint::class.java
            )
            val repository = entryPoint.documentRepository()
            repository.getDocuments(page = 1, pageSize = 5).results.take(5)
        } catch (e: IllegalStateException) {
            null
        } catch (e: Exception) {
            emptyList()
        }

        provideContent {
            Column(modifier = GlanceModifier.fillMaxSize().padding(8.dp)) {
                when {
                    documents == null -> Text(text = "Nicht angemeldet")
                    documents.isEmpty() -> Text(text = "Keine Dokumente")
                    else -> {
                        LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                            items(documents) { document ->
                                Column(
                                    modifier = GlanceModifier
                                        .fillMaxWidth()
                                        .padding(4.dp)
                                        .clickable(
                                            actionStartActivity<MainActivity>(
                                                parameters = actionParametersOf(documentIdKey to document.id)
                                            )
                                        )
                                ) {
                                    Text(text = document.title, style = TextStyle(color = ColorProvider(Color.Black)))
                                    Text(text = document.created, style = TextStyle(color = ColorProvider(Color.DarkGray)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
