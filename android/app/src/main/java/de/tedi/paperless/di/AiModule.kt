package de.tedi.paperless.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import de.tedi.paperless.ai.AiSummaryProvider
import de.tedi.paperless.ai.CloudSummaryProvider
import de.tedi.paperless.ai.GeminiNanoSummaryProvider
import de.tedi.paperless.data.local.SecureTokenStore
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AiModule {
    @Provides
    @Named("onDevice")
    @Singleton
    fun provideOnDeviceProvider(@ApplicationContext context: Context): AiSummaryProvider =
        GeminiNanoSummaryProvider(context)

    @Provides
    @Named("cloud")
    @Singleton
    fun provideCloudProvider(secureTokenStore: SecureTokenStore): AiSummaryProvider =
        CloudSummaryProvider(secureTokenStore)
}
