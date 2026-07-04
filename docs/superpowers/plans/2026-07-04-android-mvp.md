# Paperless TeDi Android MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native Android client for Paperless-ngx (Kotlin + Jetpack Compose) covering login/multi-account, document list/detail, tag/correspondent/type management, upload, camera scanning, biometric lock, and a basic AI summarization/auto-tagging adapter — reaching a state that runs and is testable in the Android emulator.

**Architecture:** MVVM + Repository pattern. `ui/` (Compose screens) → `viewmodel/` → `repository/` → `network/` (Retrofit/OkHttp) + `data/local/` (Room for accounts + offline document cache). Auth mirrors `Paperless24/Services/PaperlessAPI.swift`: `POST /api/token/` token exchange, `Authorization: Token <token>` header on all calls.

**Tech Stack:** Kotlin, Jetpack Compose (Material 3), Retrofit + OkHttp + Moshi, Room, Hilt (DI), EncryptedSharedPreferences/Keystore, ML Kit Document Scanner, AndroidX Biometric, JUnit + Turbine + MockWebServer.

Package name: `de.tedi.paperless`. Module: single `app` module (no multi-module split needed at MVP scale).

---

## Task 0: Toolchain & Project Scaffold

**Files:**
- Create: `android/` (new Gradle root)
- Create: `android/settings.gradle.kts`
- Create: `android/build.gradle.kts`
- Create: `android/gradle/libs.versions.toml`
- Create: `android/app/build.gradle.kts`
- Create: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/java/de/tedi/paperless/PaperlessApp.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/MainActivity.kt`
- Create: `android/gradle.properties`

- [ ] **Step 1: Install JDK, Android SDK command-line tools, Gradle via Homebrew**

Run:
```bash
brew install --cask temurin17
brew install --cask android-commandlinetools
```
Set env vars in `~/.zshrc` (or session):
```bash
export ANDROID_HOME="$(brew --prefix)/share/android-commandlinetools"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
```
Then:
```bash
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" "emulator" "system-images;android-34;google_apis;arm64-v8a"
avdmanager create avd -n Pixel_API_34 -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6
```
Expected: `adb --version` and `java -version` (17.x) both succeed.

- [ ] **Step 2: Scaffold Gradle project files**

`android/settings.gradle.kts`:
```kotlin
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "PaperlessTeDi"
include(":app")
```

`android/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("com.google.dagger.hilt.android") version "2.51.1" apply false
    id("com.google.devtools.ksp") version "1.9.24-1.0.20" apply false
}
```

`android/app/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.dagger.hilt.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "de.tedi.paperless"
    compileSdk = 34

    defaultConfig {
        applicationId = "de.tedi.paperless"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    packaging { resources.excludes.add("/META-INF/{AL2.0,LGPL2.1}") }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.navigation:navigation-compose:2.7.7")

    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-moshi:2.11.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.squareup.moshi:moshi-kotlin:1.15.1")
    ksp("com.squareup.moshi:moshi-kotlin-codegen:1.15.1")

    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    implementation("com.google.dagger:hilt-android:2.51.1")
    ksp("com.google.dagger:hilt-android-compiler:2.51.1")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")

    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0-beta1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("app.cash.turbine:turbine:1.1.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
```

`android/app/src/main/AndroidManifest.xml`:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <application
        android:name=".PaperlessApp"
        android:allowBackup="false"
        android:label="Paperless TeDi"
        android:theme="@style/Theme.PaperlessTeDi"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:theme="@style/Theme.PaperlessTeDi">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

`android/app/src/main/java/de/tedi/paperless/PaperlessApp.kt`:
```kotlin
package de.tedi.paperless

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class PaperlessApp : Application()
```

`android/app/src/main/java/de/tedi/paperless/MainActivity.kt`:
```kotlin
package de.tedi.paperless

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { Text("Paperless TeDi") }
    }
}
```

`android/gradle.properties`:
```
android.useAndroidX=true
kotlin.code.style=official
```

- [ ] **Step 3: Build the empty scaffold**

Run: `cd android && gradle wrapper --gradle-version 8.7 && ./gradlew assembleDebug`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Launch emulator and install**

Run: `emulator -avd Pixel_API_34 -no-snapshot &` then `./gradlew installDebug`
Expected: app installs, launching it shows "Paperless TeDi" text screen.

- [ ] **Step 5: Commit**

```bash
cd "/Users/thomas/Developer/Paperless TeDi"
git add android/
git commit -m "feat(android): scaffold Gradle project with Compose + Hilt"
```

---

## Task 1: Network Layer — API Models & Retrofit Service

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/network/model/Document.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/network/model/Tag.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/network/model/Correspondent.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/network/model/DocumentType.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/network/model/PagedResponse.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/network/PaperlessService.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/network/RetrofitFactory.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/network/PaperlessServiceTest.kt`

- [ ] **Step 1: Define data models**

`Document.kt`:
```kotlin
package de.tedi.paperless.network.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Document(
    val id: Int,
    val title: String,
    val content: String? = null,
    val created: String,
    val added: String? = null,
    val correspondent: Int? = null,
    @Json(name = "document_type") val documentType: Int? = null,
    @Json(name = "archive_serial_number") val archiveSerialNumber: Int? = null,
    val tags: List<Int> = emptyList()
)
```

`Tag.kt`:
```kotlin
package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Tag(val id: Int, val name: String, val colour: String? = null)
```

`Correspondent.kt`:
```kotlin
package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class Correspondent(val id: Int, val name: String)
```

`DocumentType.kt`:
```kotlin
package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class DocumentType(val id: Int, val name: String)
```

`PagedResponse.kt`:
```kotlin
package de.tedi.paperless.network.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class PagedResponse<T>(
    val count: Int,
    val next: String?,
    val previous: String?,
    val results: List<T>
)
```

- [ ] **Step 2: Define Retrofit service interface**

`PaperlessService.kt`:
```kotlin
package de.tedi.paperless.network

import de.tedi.paperless.network.model.*
import okhttp3.MultipartBody
import retrofit2.http.*

data class TokenRequest(val username: String, val password: String, val code: String? = null)
data class TokenResponse(val token: String)

interface PaperlessService {
    @POST("api/token/")
    suspend fun fetchToken(@Body request: TokenRequest): TokenResponse

    @GET("api/documents/")
    suspend fun getDocuments(
        @Query("page") page: Int,
        @Query("page_size") pageSize: Int,
        @Query("ordering") ordering: String = "-created"
    ): PagedResponse<Document>

    @GET("api/documents/")
    suspend fun searchDocuments(
        @Query("query") query: String,
        @Query("page") page: Int,
        @Query("page_size") pageSize: Int
    ): PagedResponse<Document>

    @GET("api/documents/{id}/")
    suspend fun getDocument(@Path("id") id: Int): Document

    @GET("api/tags/")
    suspend fun getTags(@Query("page_size") pageSize: Int = 100): PagedResponse<Tag>

    @GET("api/correspondents/")
    suspend fun getCorrespondents(@Query("page_size") pageSize: Int = 100): PagedResponse<Correspondent>

    @GET("api/document_types/")
    suspend fun getDocumentTypes(@Query("page_size") pageSize: Int = 100): PagedResponse<DocumentType>

    @Multipart
    @POST("api/documents/post_document/")
    suspend fun uploadDocument(@Part file: MultipartBody.Part): retrofit2.Response<Unit>
}
```

- [ ] **Step 3: Retrofit factory that builds a per-account client**

`RetrofitFactory.kt`:
```kotlin
package de.tedi.paperless.network

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

object RetrofitFactory {
    fun create(serverUrl: String, token: String): PaperlessService {
        val cleanUrl = serverUrl.trimEnd('/').let {
            if (it.startsWith("http")) it else "http://$it"
        }
        val authInterceptor = Interceptor { chain ->
            val request = chain.request().newBuilder()
                .addHeader("Authorization", "Token $token")
                .build()
            chain.proceed(request)
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .build()
        val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
        return Retrofit.Builder()
            .baseUrl("$cleanUrl/")
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(PaperlessService::class.java)
    }

    fun createUnauthenticated(serverUrl: String): PaperlessService {
        val cleanUrl = serverUrl.trimEnd('/').let {
            if (it.startsWith("http")) it else "http://$it"
        }
        val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
        return Retrofit.Builder()
            .baseUrl("$cleanUrl/")
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(PaperlessService::class.java)
    }
}
```

- [ ] **Step 4: Write failing test against MockWebServer**

`PaperlessServiceTest.kt`:
```kotlin
package de.tedi.paperless.network

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals

class PaperlessServiceTest {
    private lateinit var server: MockWebServer
    private lateinit var service: PaperlessService

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        service = RetrofitFactory.create(server.url("/").toString(), "test-token")
    }

    @After
    fun tearDown() { server.shutdown() }

    @Test
    fun `getDocuments parses paged response and sends auth header`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"count":1,"next":null,"previous":null,"results":[
                    {"id":1,"title":"Rechnung","created":"2026-01-01T00:00:00Z","tags":[1,2]}
                ]}"""
            ).setResponseCode(200)
        )

        val page = service.getDocuments(page = 1, pageSize = 25)

        assertEquals(1, page.results.size)
        assertEquals("Rechnung", page.results[0].title)
        val recorded = server.takeRequest()
        assertEquals("Token test-token", recorded.getHeader("Authorization"))
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.network.PaperlessServiceTest"`
Expected: FAIL (classes not resolvable / test not yet compiling if models missing — verify it fails for the right reason, i.e. before this task it wouldn't exist).

- [ ] **Step 5: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.network.PaperlessServiceTest"`
Expected: `BUILD SUCCESSFUL`, 1 test passed.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/network android/app/src/test
git commit -m "feat(android): add Retrofit network layer for Paperless-ngx API"
```

---

## Task 2: Local Storage — Room Account Database + Encrypted Token Storage

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/data/local/AccountEntity.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/data/local/AccountDao.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/data/local/AppDatabase.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/data/local/SecureTokenStore.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/data/local/AccountDaoTest.kt`

- [ ] **Step 1: Account entity + DAO**

`AccountEntity.kt`:
```kotlin
package de.tedi.paperless.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "accounts")
data class AccountEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val serverUrl: String,
    val username: String,
    val isActive: Boolean = false
)
```

`AccountDao.kt`:
```kotlin
package de.tedi.paperless.data.local

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface AccountDao {
    @Query("SELECT * FROM accounts")
    fun observeAll(): Flow<List<AccountEntity>>

    @Query("SELECT * FROM accounts WHERE isActive = 1 LIMIT 1")
    suspend fun getActive(): AccountEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(account: AccountEntity): Long

    @Query("UPDATE accounts SET isActive = 0")
    suspend fun clearActive()

    @Query("UPDATE accounts SET isActive = 1 WHERE id = :id")
    suspend fun setActive(id: Long)

    @Delete
    suspend fun delete(account: AccountEntity)
}
```

`AppDatabase.kt`:
```kotlin
package de.tedi.paperless.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [AccountEntity::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun accountDao(): AccountDao
}
```

- [ ] **Step 2: Secure token store keyed by account id**

`SecureTokenStore.kt`:
```kotlin
package de.tedi.paperless.data.local

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class SecureTokenStore(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "paperless_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveToken(accountId: Long, token: String) {
        prefs.edit().putString("token_$accountId", token).apply()
    }

    fun getToken(accountId: Long): String? = prefs.getString("token_$accountId", null)

    fun removeToken(accountId: Long) {
        prefs.edit().remove("token_$accountId").apply()
    }
}
```

- [ ] **Step 3: Write failing Room test (in-memory DB)**

Add test dependency to `app/build.gradle.kts` dependencies block:
```kotlin
testImplementation("androidx.room:room-testing:2.6.1")
testImplementation("org.robolectric:robolectric:4.13")
```

`AccountDaoTest.kt`:
```kotlin
package de.tedi.paperless.data.local

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertEquals
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
class AccountDaoTest {
    private lateinit var db: AppDatabase
    private lateinit var dao: AccountDao

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.accountDao()
    }

    @After
    fun tearDown() { db.close() }

    @Test
    fun `setActive marks only one account active`() = runTest {
        val id1 = dao.insert(AccountEntity(serverUrl = "https://a.example", username = "u1"))
        val id2 = dao.insert(AccountEntity(serverUrl = "https://b.example", username = "u2"))

        dao.clearActive()
        dao.setActive(id2)

        val active = dao.getActive()
        assertEquals(id2, active?.id)
    }

    @Test
    fun `getActive returns null when no account is active`() = runTest {
        dao.insert(AccountEntity(serverUrl = "https://a.example", username = "u1"))
        assertNull(dao.getActive())
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.data.local.AccountDaoTest"`
Expected: FAIL (AppDatabase/AccountDao not compiled into test task yet — first run after adding files should compile and pass; if it fails, verify Robolectric config in step 4 first).

- [ ] **Step 4: Add Robolectric config and rerun**

In `app/build.gradle.kts`, inside `android {}` block add:
```kotlin
testOptions {
    unitTests { isIncludeAndroidResources = true }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.data.local.AccountDaoTest"`
Expected: `BUILD SUCCESSFUL`, 2 tests passed.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/data android/app/src/test android/app/build.gradle.kts
git commit -m "feat(android): add Room account storage + encrypted token store"
```

---

## Task 3: Repository Layer — Auth & Documents

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/repository/AuthRepository.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/repository/DocumentRepository.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/repository/ServiceProvider.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/repository/AuthRepositoryTest.kt`

- [ ] **Step 1: ServiceProvider — builds a PaperlessService for the active account**

```kotlin
package de.tedi.paperless.repository

import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.SecureTokenStore
import de.tedi.paperless.network.PaperlessService
import de.tedi.paperless.network.RetrofitFactory
import javax.inject.Inject

class ServiceProvider @Inject constructor(
    private val accountDao: AccountDao,
    private val tokenStore: SecureTokenStore
) {
    suspend fun current(): PaperlessService? {
        val account = accountDao.getActive() ?: return null
        val token = tokenStore.getToken(account.id) ?: return null
        return RetrofitFactory.create(account.serverUrl, token)
    }
}
```

- [ ] **Step 2: AuthRepository — login/logout/account switching**

```kotlin
package de.tedi.paperless.repository

import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.AccountEntity
import de.tedi.paperless.data.local.SecureTokenStore
import de.tedi.paperless.network.RetrofitFactory
import de.tedi.paperless.network.TokenRequest
import javax.inject.Inject

sealed class LoginResult {
    data class Success(val accountId: Long) : LoginResult()
    object OtpRequired : LoginResult()
    data class Failure(val message: String) : LoginResult()
}

class AuthRepository @Inject constructor(
    private val accountDao: AccountDao,
    private val tokenStore: SecureTokenStore
) {
    suspend fun login(serverUrl: String, username: String, password: String, otp: String? = null): LoginResult {
        return try {
            val service = RetrofitFactory.createUnauthenticated(serverUrl)
            val response = service.fetchToken(TokenRequest(username, password, otp))
            accountDao.clearActive()
            val id = accountDao.insert(
                AccountEntity(serverUrl = serverUrl, username = username, isActive = true)
            )
            tokenStore.saveToken(id, response.token)
            LoginResult.Success(id)
        } catch (e: retrofit2.HttpException) {
            val body = e.response()?.errorBody()?.string().orEmpty().lowercase()
            val otpKeywords = listOf("otp", "totp", "mfa", "2fa", "one-time")
            if (otp == null && otpKeywords.any { body.contains(it) }) {
                LoginResult.OtpRequired
            } else {
                LoginResult.Failure("Anmeldung fehlgeschlagen (${e.code()})")
            }
        } catch (e: Exception) {
            LoginResult.Failure(e.message ?: "Unbekannter Fehler")
        }
    }

    suspend fun switchAccount(accountId: Long) {
        accountDao.clearActive()
        accountDao.setActive(accountId)
    }

    suspend fun removeAccount(account: AccountEntity) {
        tokenStore.removeToken(account.id)
        accountDao.delete(account)
    }
}
```

- [ ] **Step 3: DocumentRepository — paged fetch + search**

```kotlin
package de.tedi.paperless.repository

import de.tedi.paperless.network.model.Document
import de.tedi.paperless.network.model.PagedResponse
import javax.inject.Inject

class DocumentRepository @Inject constructor(
    private val serviceProvider: ServiceProvider
) {
    suspend fun getDocuments(page: Int, pageSize: Int = 25): PagedResponse<Document> {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.getDocuments(page = page, pageSize = pageSize)
    }

    suspend fun search(query: String, page: Int = 1, pageSize: Int = 25): PagedResponse<Document> {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.searchDocuments(query = query, page = page, pageSize = pageSize)
    }

    suspend fun getDocument(id: Int): Document {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.getDocument(id)
    }
}
```

- [ ] **Step 4: Write failing test for OTP-required detection**

```kotlin
package de.tedi.paperless.repository

import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.SecureTokenStore
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertTrue

class AuthRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var repository: AuthRepository
    private val accountDao: AccountDao = mock()
    private val tokenStore: SecureTokenStore = mock()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        repository = AuthRepository(accountDao, tokenStore)
    }

    @After
    fun tearDown() { server.shutdown() }

    @Test
    fun `login returns OtpRequired when server responds 401 with otp keyword`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401).setBody("""{"non_field_errors":["Please enter your OTP code."]}"""))

        val result = repository.login(server.url("/").toString(), "user", "pass")

        assertTrue(result is LoginResult.OtpRequired)
    }
}
```

Add to `app/build.gradle.kts` test deps: `testImplementation("org.mockito.kotlin:mockito-kotlin:5.4.0")`

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.repository.AuthRepositoryTest"`
Expected: FAIL until files above exist, then PASS.

- [ ] **Step 5: Run full test suite to confirm no regressions**

Run: `./gradlew testDebugUnitTest`
Expected: `BUILD SUCCESSFUL`, all tests passed.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/repository android/app/src/test android/app/build.gradle.kts
git commit -m "feat(android): add auth and document repositories"
```

---

## Task 4: Hilt DI Modules

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/di/AppModule.kt`

- [ ] **Step 1: Provide Room DB, DAO, SecureTokenStore as singletons**

```kotlin
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
```

- [ ] **Step 2: Build to confirm Hilt graph resolves**

Run: `./gradlew assembleDebug`
Expected: `BUILD SUCCESSFUL` (Hilt annotation processing succeeds, no missing binding errors).

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/di
git commit -m "feat(android): add Hilt DI module for database and secure storage"
```

---

## Task 5: Login Screen

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/LoginViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/login/LoginScreen.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/viewmodel/LoginViewModelTest.kt`

- [ ] **Step 1: Write failing ViewModel test**

```kotlin
package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.repository.AuthRepository
import de.tedi.paperless.repository.LoginResult
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertTrue

class LoginViewModelTest {
    @Test
    fun `successful login updates state to LoggedIn`() = runTest {
        val repo: AuthRepository = mock()
        whenever(repo.login("https://s", "u", "p", null)).thenReturn(LoginResult.Success(1L))
        val vm = LoginViewModel(repo)

        vm.state.test {
            assertTrue(awaitItem() is LoginUiState.Idle)
            vm.login("https://s", "u", "p")
            assertTrue(awaitItem() is LoginUiState.Loading)
            assertTrue(awaitItem() is LoginUiState.LoggedIn)
        }
    }

    @Test
    fun `otp required shows OtpNeeded state`() = runTest {
        val repo: AuthRepository = mock()
        whenever(repo.login("https://s", "u", "p", null)).thenReturn(LoginResult.OtpRequired)
        val vm = LoginViewModel(repo)

        vm.state.test {
            awaitItem()
            vm.login("https://s", "u", "p")
            awaitItem()
            assertTrue(awaitItem() is LoginUiState.OtpNeeded)
        }
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.LoginViewModelTest"`
Expected: FAIL (LoginViewModel/LoginUiState don't exist).

- [ ] **Step 2: Implement LoginViewModel**

```kotlin
package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.repository.AuthRepository
import de.tedi.paperless.repository.LoginResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class LoginUiState {
    object Idle : LoginUiState()
    object Loading : LoginUiState()
    object OtpNeeded : LoginUiState()
    data class LoggedIn(val accountId: Long) : LoginUiState()
    data class Error(val message: String) : LoginUiState()
}

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {
    private val _state = MutableStateFlow<LoginUiState>(LoginUiState.Idle)
    val state: StateFlow<LoginUiState> = _state

    fun login(serverUrl: String, username: String, password: String, otp: String? = null) {
        viewModelScope.launch {
            _state.value = LoginUiState.Loading
            when (val result = authRepository.login(serverUrl, username, password, otp)) {
                is LoginResult.Success -> _state.value = LoginUiState.LoggedIn(result.accountId)
                is LoginResult.OtpRequired -> _state.value = LoginUiState.OtpNeeded
                is LoginResult.Failure -> _state.value = LoginUiState.Error(result.message)
            }
        }
    }
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.LoginViewModelTest"`
Expected: `BUILD SUCCESSFUL`, 2 tests passed.

- [ ] **Step 4: Compose LoginScreen**

```kotlin
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
```

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/viewmodel/LoginViewModel.kt android/app/src/main/java/de/tedi/paperless/ui/login android/app/src/test
git commit -m "feat(android): add login screen with 2FA support"
```

---

## Task 6: Document List Screen

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/DocumentListViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/documents/DocumentListScreen.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/viewmodel/DocumentListViewModelTest.kt`

- [ ] **Step 1: Write failing ViewModel test**

```kotlin
package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.network.model.PagedResponse
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

class DocumentListViewModelTest {
    @Test
    fun `loadFirstPage populates documents from repository`() = runTest {
        val repo: DocumentRepository = mock()
        val doc = Document(id = 1, title = "Rechnung", created = "2026-01-01T00:00:00Z")
        whenever(repo.getDocuments(1, 25)).thenReturn(PagedResponse(1, null, null, listOf(doc)))
        val vm = DocumentListViewModel(repo)

        vm.state.test {
            assertEquals(emptyList(), awaitItem().documents)
            vm.loadFirstPage()
            assertEquals(listOf(doc), awaitItem().documents)
        }
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.DocumentListViewModelTest"`
Expected: FAIL (class doesn't exist).

- [ ] **Step 2: Implement DocumentListViewModel**

```kotlin
package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DocumentListState(
    val documents: List<Document> = emptyList(),
    val isLoading: Boolean = false,
    val hasNext: Boolean = false,
    val error: String? = null,
    val page: Int = 1
)

@HiltViewModel
class DocumentListViewModel @Inject constructor(
    private val repository: DocumentRepository
) : ViewModel() {
    private val _state = MutableStateFlow(DocumentListState())
    val state: StateFlow<DocumentListState> = _state

    fun loadFirstPage() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val result = repository.getDocuments(page = 1)
                _state.update {
                    it.copy(documents = result.results, hasNext = result.next != null, page = 1, isLoading = false)
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun loadNextPage() {
        val current = _state.value
        if (!current.hasNext || current.isLoading) return
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }
            try {
                val nextPage = current.page + 1
                val result = repository.getDocuments(page = nextPage)
                _state.update {
                    it.copy(
                        documents = it.documents + result.results,
                        hasNext = result.next != null,
                        page = nextPage,
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun search(query: String) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val result = repository.search(query)
                _state.update {
                    it.copy(documents = result.results, hasNext = result.next != null, page = 1, isLoading = false)
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.DocumentListViewModelTest"`
Expected: `BUILD SUCCESSFUL`, 1 test passed.

- [ ] **Step 4: Compose DocumentListScreen**

```kotlin
package de.tedi.paperless.ui.documents

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.viewmodel.DocumentListViewModel

@Composable
fun DocumentListScreen(
    onDocumentClick: (Int) -> Unit,
    viewModel: DocumentListViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) { viewModel.loadFirstPage() }

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            label = { Text("Suche") },
            trailingIcon = {
                IconButton(onClick = { viewModel.search(query) }) {
                    Icon(Icons.Default.Search, contentDescription = "Suchen")
                }
            },
            modifier = Modifier.fillMaxWidth().padding(16.dp)
        )
        if (state.error != null) {
            Text(state.error!!, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp))
        }
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(state.documents, key = { it.id }) { doc: Document ->
                ListItem(
                    headlineContent = { Text(doc.title) },
                    supportingContent = { Text(doc.created) },
                    modifier = Modifier.clickable { onDocumentClick(doc.id) }
                )
                HorizontalDivider()
            }
            if (state.hasNext) {
                item {
                    LaunchedEffect(Unit) { viewModel.loadNextPage() }
                    Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
            }
        }
    }
}
```

Note: add `import androidx.compose.foundation.clickable` and `androidx.compose.ui.Alignment` to imports above.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/viewmodel/DocumentListViewModel.kt android/app/src/main/java/de/tedi/paperless/ui/documents android/app/src/test
git commit -m "feat(android): add paginated document list screen with search"
```

---

## Task 7: Document Detail Screen (PDF Viewer + Metadata)

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/DocumentDetailViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/documents/DocumentDetailScreen.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/documents/PdfViewer.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/viewmodel/DocumentDetailViewModelTest.kt`

- [ ] **Step 1: Write failing ViewModel test**

```kotlin
package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

class DocumentDetailViewModelTest {
    @Test
    fun `load fetches document by id`() = runTest {
        val repo: DocumentRepository = mock()
        val doc = Document(id = 42, title = "Vertrag", created = "2026-01-01T00:00:00Z")
        whenever(repo.getDocument(42)).thenReturn(doc)
        val vm = DocumentDetailViewModel(repo)

        vm.state.test {
            assertEquals(null, awaitItem().document)
            vm.load(42)
            assertEquals(doc, awaitItem().document)
        }
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.DocumentDetailViewModelTest"`
Expected: FAIL.

- [ ] **Step 2: Implement DocumentDetailViewModel**

```kotlin
package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.network.model.Document
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DocumentDetailState(
    val document: Document? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class DocumentDetailViewModel @Inject constructor(
    private val repository: DocumentRepository
) : ViewModel() {
    private val _state = MutableStateFlow(DocumentDetailState())
    val state: StateFlow<DocumentDetailState> = _state

    fun load(id: Int) {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val doc = repository.getDocument(id)
                _state.update { it.copy(document = doc, isLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.DocumentDetailViewModelTest"`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: PDF viewer using AndroidX PdfRenderer**

```kotlin
package de.tedi.paperless.ui.documents

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import java.io.File

@Composable
fun PdfViewer(pdfFile: File) {
    val pages = remember(pdfFile) { mutableStateListOf<Bitmap>() }

    LaunchedEffect(pdfFile) {
        pages.clear()
        val descriptor = ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY)
        PdfRenderer(descriptor).use { renderer ->
            for (i in 0 until renderer.pageCount) {
                renderer.openPage(i).use { page ->
                    val bitmap = Bitmap.createBitmap(page.width * 2, page.height * 2, Bitmap.Config.ARGB_8888)
                    page.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    pages.add(bitmap)
                }
            }
        }
    }

    LazyColumn {
        items(pages) { bitmap ->
            Image(bitmap = bitmap.asImageBitmap(), contentDescription = null, modifier = Modifier.fillMaxWidth())
        }
    }
}
```

- [ ] **Step 5: DocumentDetailScreen wiring metadata + PDF download**

```kotlin
package de.tedi.paperless.ui.documents

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.DocumentDetailViewModel

@Composable
fun DocumentDetailScreen(
    documentId: Int,
    viewModel: DocumentDetailViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(documentId) { viewModel.load(documentId) }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        if (state.isLoading) {
            CircularProgressIndicator()
        }
        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        state.document?.let { doc ->
            Text(doc.title, style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            Text("Erstellt: ${doc.created}")
            Spacer(Modifier.height(8.dp))
            Text("Tags: ${doc.tags.joinToString(", ")}")
        }
    }
}
```

Add to `PaperlessService.kt`:
```kotlin
    @GET("api/documents/{id}/download/")
    @Streaming
    suspend fun downloadDocument(@Path("id") id: Int): retrofit2.Response<okhttp3.ResponseBody>
```

**Files (update to add):**
- Modify: `android/app/src/main/java/de/tedi/paperless/network/PaperlessService.kt` — add `downloadDocument`
- Modify: `android/app/src/main/java/de/tedi/paperless/repository/DocumentRepository.kt` — add `downloadDocument(id: Int): okhttp3.ResponseBody`
- Modify: `android/app/src/main/java/de/tedi/paperless/viewmodel/DocumentDetailViewModel.kt` — download PDF to app cache dir on load, expose `pdfFile: File?` in state
- Modify: `android/app/src/main/java/de/tedi/paperless/ui/documents/DocumentDetailScreen.kt` — render `PdfViewer(state.pdfFile)` when non-null

Add to `DocumentRepository.kt`:
```kotlin
    suspend fun downloadDocument(id: Int): okhttp3.ResponseBody {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        return service.downloadDocument(id).body() ?: throw IllegalStateException("Empty PDF body")
    }
```

Update `DocumentDetailViewModel.kt` state and `load()`:
```kotlin
data class DocumentDetailState(
    val document: Document? = null,
    val pdfFile: java.io.File? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)
```
Add constructor param `@ApplicationContext private val context: android.content.Context` (requires `@Inject constructor` update) and inside `load()`, after fetching `doc`, also fetch and write the PDF:
```kotlin
                val doc = repository.getDocument(id)
                val pdfBody = repository.downloadDocument(id)
                val file = java.io.File(context.cacheDir, "doc_$id.pdf")
                file.outputStream().use { out -> pdfBody.byteStream().copyTo(out) }
                _state.update { it.copy(document = doc, pdfFile = file, isLoading = false) }
```
(Replace the existing simpler `load()` body from Step 2 with this version.)

Update `DocumentDetailScreen.kt` to render the viewer:
```kotlin
        state.pdfFile?.let { file -> PdfViewer(file) }
```

- [ ] **Step 6: Rebuild and run full test suite**

Run: `./gradlew testDebugUnitTest assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless
git commit -m "feat(android): add document detail screen with PDF rendering"
```

---

## Task 8: Tags / Correspondents / Document Types Management

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/repository/MetadataRepository.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/MetadataViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/metadata/MetadataScreen.kt`
- Modify: `android/app/src/main/java/de/tedi/paperless/network/PaperlessService.kt` — add create/update/delete endpoints
- Test: `android/app/src/test/java/de/tedi/paperless/viewmodel/MetadataViewModelTest.kt`

- [ ] **Step 1: Extend PaperlessService with CRUD endpoints**

Add to `PaperlessService.kt`:
```kotlin
    @POST("api/tags/")
    suspend fun createTag(@Body body: Map<String, String>): Tag

    @PATCH("api/tags/{id}/")
    suspend fun updateTag(@Path("id") id: Int, @Body body: Map<String, String>): Tag

    @DELETE("api/tags/{id}/")
    suspend fun deleteTag(@Path("id") id: Int): retrofit2.Response<Unit>

    @POST("api/correspondents/")
    suspend fun createCorrespondent(@Body body: Map<String, String>): Correspondent

    @DELETE("api/correspondents/{id}/")
    suspend fun deleteCorrespondent(@Path("id") id: Int): retrofit2.Response<Unit>

    @POST("api/document_types/")
    suspend fun createDocumentType(@Body body: Map<String, String>): DocumentType

    @DELETE("api/document_types/{id}/")
    suspend fun deleteDocumentType(@Path("id") id: Int): retrofit2.Response<Unit>
```

- [ ] **Step 2: MetadataRepository**

```kotlin
package de.tedi.paperless.repository

import de.tedi.paperless.network.model.Correspondent
import de.tedi.paperless.network.model.DocumentType
import de.tedi.paperless.network.model.Tag
import javax.inject.Inject

class MetadataRepository @Inject constructor(
    private val serviceProvider: ServiceProvider
) {
    suspend fun getTags(): List<Tag> =
        (serviceProvider.current() ?: error("No active account")).getTags().results

    suspend fun createTag(name: String): Tag =
        (serviceProvider.current() ?: error("No active account")).createTag(mapOf("name" to name))

    suspend fun deleteTag(id: Int) {
        (serviceProvider.current() ?: error("No active account")).deleteTag(id)
    }

    suspend fun getCorrespondents(): List<Correspondent> =
        (serviceProvider.current() ?: error("No active account")).getCorrespondents().results

    suspend fun createCorrespondent(name: String): Correspondent =
        (serviceProvider.current() ?: error("No active account")).createCorrespondent(mapOf("name" to name))

    suspend fun deleteCorrespondent(id: Int) {
        (serviceProvider.current() ?: error("No active account")).deleteCorrespondent(id)
    }

    suspend fun getDocumentTypes(): List<DocumentType> =
        (serviceProvider.current() ?: error("No active account")).getDocumentTypes().results

    suspend fun createDocumentType(name: String): DocumentType =
        (serviceProvider.current() ?: error("No active account")).createDocumentType(mapOf("name" to name))

    suspend fun deleteDocumentType(id: Int) {
        (serviceProvider.current() ?: error("No active account")).deleteDocumentType(id)
    }
}
```

- [ ] **Step 3: Write failing test for tag creation**

```kotlin
package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.network.model.Tag
import de.tedi.paperless.repository.MetadataRepository
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

class MetadataViewModelTest {
    @Test
    fun `createTag appends new tag to list`() = runTest {
        val repo: MetadataRepository = mock()
        whenever(repo.getTags()).thenReturn(emptyList())
        whenever(repo.createTag("Steuer")).thenReturn(Tag(id = 1, name = "Steuer"))
        val vm = MetadataViewModel(repo)

        vm.state.test {
            assertEquals(emptyList(), awaitItem().tags)
            vm.loadTags()
            assertEquals(emptyList(), awaitItem().tags)
            vm.createTag("Steuer")
            assertEquals(listOf(Tag(id = 1, name = "Steuer")), awaitItem().tags)
        }
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.MetadataViewModelTest"`
Expected: FAIL.

- [ ] **Step 4: Implement MetadataViewModel**

```kotlin
package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.network.model.Tag
import de.tedi.paperless.repository.MetadataRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MetadataState(val tags: List<Tag> = emptyList())

@HiltViewModel
class MetadataViewModel @Inject constructor(
    private val repository: MetadataRepository
) : ViewModel() {
    private val _state = MutableStateFlow(MetadataState())
    val state: StateFlow<MetadataState> = _state

    fun loadTags() {
        viewModelScope.launch {
            _state.update { it.copy(tags = repository.getTags()) }
        }
    }

    fun createTag(name: String) {
        viewModelScope.launch {
            val tag = repository.createTag(name)
            _state.update { it.copy(tags = it.tags + tag) }
        }
    }

    fun deleteTag(id: Int) {
        viewModelScope.launch {
            repository.deleteTag(id)
            _state.update { it.copy(tags = it.tags.filterNot { t -> t.id == id }) }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.MetadataViewModelTest"`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: MetadataScreen (tags list + add dialog)**

```kotlin
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
```

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless
git commit -m "feat(android): add tag/correspondent/document-type management"
```

---

## Task 9: Upload (Gallery/Files) & ML Kit Camera Scanner

**Files:**
- Modify: `android/app/src/main/java/de/tedi/paperless/repository/DocumentRepository.kt` — add `uploadFile`
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/UploadViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/upload/UploadScreen.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/upload/ScannerLauncher.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/viewmodel/UploadViewModelTest.kt`

- [ ] **Step 1: Add uploadFile to DocumentRepository**

```kotlin
    suspend fun uploadFile(fileBytes: ByteArray, filename: String): Boolean {
        val service = serviceProvider.current() ?: throw IllegalStateException("No active account")
        val requestBody = fileBytes.toRequestBody("application/octet-stream".toMediaTypeOrNull())
        val part = okhttp3.MultipartBody.Part.createFormData("document", filename, requestBody)
        return service.uploadDocument(part).isSuccessful
    }
```
Add imports: `okhttp3.RequestBody.Companion.toRequestBody`, `okhttp3.MediaType.Companion.toMediaTypeOrNull`.

- [ ] **Step 2: Write failing UploadViewModel test**

```kotlin
package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertTrue

class UploadViewModelTest {
    @Test
    fun `upload success sets Success state`() = runTest {
        val repo: DocumentRepository = mock()
        whenever(repo.uploadFile(any(), any())).thenReturn(true)
        val vm = UploadViewModel(repo)

        vm.state.test {
            assertTrue(awaitItem() is UploadUiState.Idle)
            vm.upload(byteArrayOf(1, 2, 3), "scan.pdf")
            assertTrue(awaitItem() is UploadUiState.Uploading)
            assertTrue(awaitItem() is UploadUiState.Success)
        }
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.UploadViewModelTest"`
Expected: FAIL.

- [ ] **Step 3: Implement UploadViewModel**

```kotlin
package de.tedi.paperless.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import de.tedi.paperless.repository.DocumentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class UploadUiState {
    object Idle : UploadUiState()
    object Uploading : UploadUiState()
    object Success : UploadUiState()
    data class Error(val message: String) : UploadUiState()
}

@HiltViewModel
class UploadViewModel @Inject constructor(
    private val repository: DocumentRepository
) : ViewModel() {
    private val _state = MutableStateFlow<UploadUiState>(UploadUiState.Idle)
    val state: StateFlow<UploadUiState> = _state

    fun upload(bytes: ByteArray, filename: String) {
        viewModelScope.launch {
            _state.value = UploadUiState.Uploading
            _state.value = try {
                repository.uploadFile(bytes, filename)
                UploadUiState.Success
            } catch (e: Exception) {
                UploadUiState.Error(e.message ?: "Upload fehlgeschlagen")
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.viewmodel.UploadViewModelTest"`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: ML Kit scanner launcher composable**

```kotlin
package de.tedi.paperless.ui.upload

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult

@Composable
fun rememberScannerLauncher(onScanned: (GmsDocumentScanningResult) -> Unit): () -> Unit {
    val context = LocalContext.current
    val options = remember {
        GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setPageLimit(20)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
    }
    val scanner = remember { GmsDocumentScanning.getClient(options) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            GmsDocumentScanningResult.fromActivityResultIntent(result.data)?.let(onScanned)
        }
    }
    return {
        scanner.getStartScanIntent(context as Activity)
            .addOnSuccessListener { intentSender ->
                launcher.launch(androidx.activity.result.IntentSenderRequest.Builder(intentSender).build())
            }
    }
}
```

- [ ] **Step 6: UploadScreen wiring scanner + file picker**

```kotlin
package de.tedi.paperless.ui.upload

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import de.tedi.paperless.viewmodel.UploadUiState
import de.tedi.paperless.viewmodel.UploadViewModel

@Composable
fun UploadScreen(viewModel: UploadViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let {
            val bytes = context.contentResolver.openInputStream(it)?.use { s -> s.readBytes() } ?: return@let
            viewModel.upload(bytes, "upload_${System.currentTimeMillis()}.pdf")
        }
    }

    val scanLauncher = rememberScannerLauncher { result ->
        result.pdf?.uri?.let { uri ->
            val bytes = context.contentResolver.openInputStream(uri)?.use { s -> s.readBytes() } ?: return@let
            viewModel.upload(bytes, "scan_${System.currentTimeMillis()}.pdf")
        }
    }

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Button(onClick = scanLauncher, modifier = Modifier.fillMaxWidth()) { Text("Dokument scannen") }
        Spacer(Modifier.height(8.dp))
        Button(onClick = { filePicker.launch("application/pdf") }, modifier = Modifier.fillMaxWidth()) {
            Text("Datei auswählen")
        }
        Spacer(Modifier.height(16.dp))
        when (state) {
            is UploadUiState.Uploading -> CircularProgressIndicator()
            is UploadUiState.Success -> Text("Upload erfolgreich")
            is UploadUiState.Error -> Text((state as UploadUiState.Error).message, color = MaterialTheme.colorScheme.error)
            else -> {}
        }
    }
}
```

- [ ] **Step 7: Add ML Kit document scanner activity dependency check and build**

Run: `./gradlew assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless
git commit -m "feat(android): add file upload and ML Kit document scanner"
```

---

## Task 10: Biometric Lock

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/ui/auth/BiometricGate.kt`
- Modify: `android/app/src/main/java/de/tedi/paperless/MainActivity.kt` — wrap content in `BiometricGate`

- [ ] **Step 1: BiometricGate composable**

```kotlin
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
```

- [ ] **Step 2: Wire into MainActivity, switch base activity to FragmentActivity**

Modify `MainActivity.kt`:
```kotlin
package de.tedi.paperless

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.fragment.app.FragmentActivity
import dagger.hilt.android.AndroidEntryPoint
import de.tedi.paperless.ui.auth.BiometricGate

@AndroidEntryPoint
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BiometricGate(enabled = false) {
                de.tedi.paperless.ui.PaperlessNavHost()
            }
        }
    }
}
```

Note: `enabled = false` placeholder wired to a settings flag is a Phase-2 refinement (settings screen is out of MVP scope); leaving it hardcoded `false` for now is acceptable since BiometricGate itself is implemented and verifiable by flipping the literal to `true` manually during emulator testing.

Add dependency to `app/build.gradle.kts`: `implementation("androidx.fragment:fragment-ktx:1.8.2")`

- [ ] **Step 3: Build**

Run: `./gradlew assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/ui/auth android/app/src/main/java/de/tedi/paperless/MainActivity.kt android/app/build.gradle.kts
git commit -m "feat(android): add biometric lock gate"
```

---

## Task 11: Navigation Host (wires all screens together)

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/ui/PaperlessNavHost.kt`

- [ ] **Step 1: NavHost with login → list → detail → upload → metadata routes**

```kotlin
package de.tedi.paperless.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import de.tedi.paperless.ui.documents.DocumentDetailScreen
import de.tedi.paperless.ui.documents.DocumentListScreen
import de.tedi.paperless.ui.login.LoginScreen
import de.tedi.paperless.ui.metadata.MetadataScreen
import de.tedi.paperless.ui.upload.UploadScreen

@Composable
fun PaperlessNavHost() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = "login") {
        composable("login") {
            LoginScreen(onLoggedIn = { navController.navigate("documents") { popUpTo("login") { inclusive = true } } })
        }
        composable("documents") {
            DocumentListScreen(onDocumentClick = { id -> navController.navigate("documents/$id") })
        }
        composable(
            "documents/{id}",
            arguments = listOf(navArgument("id") { type = NavType.IntType })
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getInt("id") ?: return@composable
            DocumentDetailScreen(documentId = id)
        }
        composable("upload") { UploadScreen() }
        composable("metadata") { MetadataScreen() }
    }
}
```

- [ ] **Step 2: Build and install on emulator**

Run: `./gradlew installDebug`
Expected: `BUILD SUCCESSFUL`, app installs.

- [ ] **Step 3: Manual smoke test in emulator**

Launch app, verify login screen renders. This is the point where the app becomes "testable in the emulator" per the user's request — do not proceed to Task 12 without confirming this launches without crashing (`adb logcat *:E` clean of fatal exceptions from `de.tedi.paperless`).

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/ui/PaperlessNavHost.kt
git commit -m "feat(android): wire navigation host connecting all MVP screens"
```

---

## Task 12: AI Adapter — Gemini Nano (on-device) with Cloud Fallback

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/ai/AiSummaryProvider.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ai/GeminiNanoSummaryProvider.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ai/CloudSummaryProvider.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ai/AiSummaryRepository.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/ai/AiSummaryRepositoryTest.kt`

- [ ] **Step 1: Define provider interface**

```kotlin
package de.tedi.paperless.ai

interface AiSummaryProvider {
    suspend fun isAvailable(): Boolean
    suspend fun summarize(text: String): String
    suspend fun suggestTags(text: String, existingTags: List<String>): List<String>
}
```

- [ ] **Step 2: Write failing test for fallback behavior**

```kotlin
package de.tedi.paperless.ai

import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

class AiSummaryRepositoryTest {
    @Test
    fun `falls back to cloud provider when on-device is unavailable`() = runTest {
        val onDevice: AiSummaryProvider = mock()
        val cloud: AiSummaryProvider = mock()
        whenever(onDevice.isAvailable()).thenReturn(false)
        whenever(cloud.isAvailable()).thenReturn(true)
        whenever(cloud.summarize("text")).thenReturn("cloud summary")

        val repository = AiSummaryRepository(onDevice, cloud)

        assertEquals("cloud summary", repository.summarize("text"))
    }

    @Test
    fun `uses on-device provider when available`() = runTest {
        val onDevice: AiSummaryProvider = mock()
        val cloud: AiSummaryProvider = mock()
        whenever(onDevice.isAvailable()).thenReturn(true)
        whenever(onDevice.summarize("text")).thenReturn("on-device summary")

        val repository = AiSummaryRepository(onDevice, cloud)

        assertEquals("on-device summary", repository.summarize("text"))
    }
}
```

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.ai.AiSummaryRepositoryTest"`
Expected: FAIL (classes don't exist).

- [ ] **Step 3: Implement AiSummaryRepository with fallback logic**

```kotlin
package de.tedi.paperless.ai

import javax.inject.Inject
import javax.inject.Named

class AiSummaryRepository @Inject constructor(
    @Named("onDevice") private val onDeviceProvider: AiSummaryProvider,
    @Named("cloud") private val cloudProvider: AiSummaryProvider
) {
    private suspend fun activeProvider(): AiSummaryProvider =
        if (onDeviceProvider.isAvailable()) onDeviceProvider else cloudProvider

    suspend fun summarize(text: String): String = activeProvider().summarize(text)

    suspend fun suggestTags(text: String, existingTags: List<String>): List<String> =
        activeProvider().suggestTags(text, existingTags)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./gradlew testDebugUnitTest --tests "de.tedi.paperless.ai.AiSummaryRepositoryTest"`
Expected: `BUILD SUCCESSFUL`, 2 tests passed.

- [ ] **Step 5: GeminiNanoSummaryProvider (AICore GenerativeModel API)**

Add dependency to `app/build.gradle.kts`: `implementation("com.google.ai.edge.aicore:aicore:0.0.1-exp01")`

```kotlin
package de.tedi.paperless.ai

import android.content.Context
import com.google.ai.edge.aicore.GenerationConfig
import com.google.ai.edge.aicore.GenerativeModel
import javax.inject.Inject
import javax.inject.Named

class GeminiNanoSummaryProvider @Inject constructor(
    @param:javax.inject.Named("appContext") private val context: Context
) : AiSummaryProvider {
    private var model: GenerativeModel? = null

    private fun getModel(): GenerativeModel {
        return model ?: GenerativeModel(
            generationConfig = GenerationConfig.Builder(context).build()
        ).also { model = it }
    }

    override suspend fun isAvailable(): Boolean = try {
        getModel(); true
    } catch (e: Exception) { false }

    override suspend fun summarize(text: String): String {
        val response = getModel().generateContent("Fasse folgenden Text in 1-3 Sätzen zusammen:\n$text")
        return response.text ?: ""
    }

    override suspend fun suggestTags(text: String, existingTags: List<String>): List<String> {
        val prompt = "Schlage passende Tags aus dieser Liste vor: ${existingTags.joinToString(", ")}\nText: $text\nAntworte nur mit einer kommagetrennten Liste."
        val response = getModel().generateContent(prompt)
        return response.text?.split(",")?.map { it.trim() }?.filter { it.isNotBlank() } ?: emptyList()
    }
}
```

- [ ] **Step 6: CloudSummaryProvider (user-supplied API key, Anthropic Messages API)**

```kotlin
package de.tedi.paperless.ai

import de.tedi.paperless.data.local.SecureTokenStore
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import javax.inject.Inject

class CloudSummaryProvider @Inject constructor(
    private val secureTokenStore: SecureTokenStore
) : AiSummaryProvider {
    private val client = OkHttpClient()

    private fun apiKey(): String? = secureTokenStore.getCloudAiApiKey()

    override suspend fun isAvailable(): Boolean = !apiKey().isNullOrBlank()

    private fun callClaude(prompt: String): String {
        val key = apiKey() ?: throw IllegalStateException("Kein API-Key hinterlegt")
        val body = JSONObject().apply {
            put("model", "claude-sonnet-5")
            put("max_tokens", 512)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", prompt)
            }))
        }.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("https://api.anthropic.com/v1/messages")
            .addHeader("x-api-key", key)
            .addHeader("anthropic-version", "2023-06-01")
            .post(body)
            .build()

        client.newCall(request).execute().use { response ->
            val json = JSONObject(response.body?.string() ?: "{}")
            return json.optJSONArray("content")?.optJSONObject(0)?.optString("text") ?: ""
        }
    }

    override suspend fun summarize(text: String): String =
        callClaude("Fasse folgenden Text in 1-3 Sätzen zusammen:\n$text")

    override suspend fun suggestTags(text: String, existingTags: List<String>): List<String> {
        val result = callClaude("Schlage passende Tags aus dieser Liste vor: ${existingTags.joinToString(", ")}\nText: $text\nAntworte nur mit einer kommagetrennten Liste.")
        return result.split(",").map { it.trim() }.filter { it.isNotBlank() }
    }
}
```

Add to `SecureTokenStore.kt`:
```kotlin
    fun saveCloudAiApiKey(key: String) { prefs.edit().putString("cloud_ai_api_key", key).apply() }
    fun getCloudAiApiKey(): String? = prefs.getString("cloud_ai_api_key", null)
```

- [ ] **Step 7: Hilt bindings for the two named providers**

Add to `di/AppModule.kt` (new `@Module` object, since these need `@Binds` in an interface-implementing module):

```kotlin
package de.tedi.paperless.di

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
    fun provideOnDeviceProvider(@ApplicationContext context: android.content.Context): AiSummaryProvider =
        GeminiNanoSummaryProvider(context)

    @Provides
    @Named("cloud")
    @Singleton
    fun provideCloudProvider(secureTokenStore: SecureTokenStore): AiSummaryProvider =
        CloudSummaryProvider(secureTokenStore)
}
```

Save as `android/app/src/main/java/de/tedi/paperless/di/AiModule.kt`.

- [ ] **Step 8: Build full project**

Run: `./gradlew testDebugUnitTest assembleDebug`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 9: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/ai android/app/src/main/java/de/tedi/paperless/di/AiModule.kt android/app/src/main/java/de/tedi/paperless/data/local/SecureTokenStore.kt android/app/build.gradle.kts android/app/src/test
git commit -m "feat(android): add on-device/cloud AI summarization adapter with fallback"
```

---

## Task 13: Final Emulator Verification

**Files:** none (verification only)

- [ ] **Step 1: Full clean build**

Run: `./gradlew clean testDebugUnitTest assembleDebug`
Expected: `BUILD SUCCESSFUL`, all unit tests pass.

- [ ] **Step 2: Install and launch on emulator**

Run:
```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n de.tedi.paperless/.MainActivity
```
Expected: app launches to login screen without crash.

- [ ] **Step 3: Check logcat for fatal errors**

Run: `adb logcat -d *:E | grep de.tedi.paperless`
Expected: no `FATAL EXCEPTION` entries.

- [ ] **Step 4: Report back to user**

Summarize: what screens exist, how to log in against a real Paperless-ngx server in the emulator, known limitations (no offline cache yet, AI cloud key must be entered manually, PDF viewer is basic), and how to take it further (Phase 2 features from the spec).
