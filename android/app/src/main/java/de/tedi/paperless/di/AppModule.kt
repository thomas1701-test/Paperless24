package de.tedi.paperless.di

import android.content.Context
import androidx.room.Room
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.AppDatabase
import de.tedi.paperless.data.local.SecureTokenStore
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, "paperless.db").build()

    @Provides
    fun provideAccountDao(db: AppDatabase): AccountDao = db.accountDao()

    @Provides
    @Singleton
    fun provideSecureTokenStore(@ApplicationContext context: Context): SecureTokenStore =
        SecureTokenStore(context)
}
