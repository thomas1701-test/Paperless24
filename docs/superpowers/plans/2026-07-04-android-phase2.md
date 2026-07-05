# Paperless TeDi Android Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the working Android MVP (Tasks 0-13, already complete on `feature/android-port`) with the "spätere Phasen" features listed in the design spec: home-screen widget, background sync/notifications, semantic archive search, on-device translation, AirScan network scanner discovery, tablet split-view layout, and Google Assistant App Actions.

**Architecture:** Same MVVM + Repository pattern as the MVP. Each feature is additive and largely independent — implement in any order, but each task must leave the project building and all tests passing.

**Tech Stack additions:** Glance (Jetpack Compose for widgets), WorkManager, ML Kit Translation, NSD (Network Service Discovery, Android's Bonjour/mDNS equivalent) for AirScan, Android App Actions (`actions.xml` + `capability` intent filters — Google Assistant's equivalent of iOS AppIntents/Siri).

Environment (same as MVP, needed each shell session):
```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
```
Run Gradle from `/Users/thomas/Developer/Paperless TeDi/android` via `./gradlew <task>`.

Known project quirks (apply proactively, from MVP implementation):
- Never use wildcard imports that could collide (e.g. `retrofit2.http.Tag` vs. model `Tag`) — explicit imports throughout.
- `@HiltViewModel` tests using `viewModelScope.launch` need `Dispatchers.setMain(StandardTestDispatcher())`/`resetMain()` in `@Before`/`@After`.
- Turbine's `state.test { }` may see extra intermediate `isLoading` emissions — verify by running the test, add `awaitItem()` calls as needed.
- `kotlin.test.*` assertions, Mockito-kotlin `mock()` on final classes, Robolectric + `androidx.test:core` for `ApplicationProvider` — all already configured in `app/build.gradle.kts`.
- If Gradle OOMs with GC-thrashing, heap is already raised in `gradle.properties`; increase further if needed.
- A dependency artifact requiring a higher `minSdk` than this project's 26 (like `com.google.ai.edge.aicore` in the MVP's Task 12) should be handled the same way: don't bump `minSdk` to fit one dependency without asking; stub the feature behind an interface instead and note it.

---

## Task 14: Home Screen Widget (Glance)

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/widget/PaperlessWidget.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/widget/PaperlessWidgetReceiver.kt`
- Modify: `android/app/build.gradle.kts` — add Glance dependency
- Modify: `android/app/src/main/AndroidManifest.xml` — register the widget receiver

- [ ] **Step 1: Add Glance dependency**

```kotlin
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
```

- [ ] **Step 2: Widget composable showing the 5 most recent documents**

`PaperlessWidget.kt` — a `GlanceAppWidget` that reads recent documents via `DocumentRepository` (injected through `EntryPointAccessors` since Glance widgets aren't part of the Compose/Hilt navigation graph) and renders a `LazyColumn`-equivalent (`LazyColumn` from `androidx.glance.appwidget.lazy`) of title + created date. Tapping an item launches `MainActivity` with an extra `documentId` that `PaperlessNavHost`/`MainActivity` reads to deep-link into `DocumentDetailScreen` (add this deep-link wiring to `MainActivity.kt`: read `intent.getIntExtra("documentId", -1)` and pass an optional start destination override into `PaperlessNavHost`).

Use a Hilt `EntryPoint` for widget DI:
```kotlin
@EntryPoint
@InstallIn(SingletonComponent::class)
interface WidgetEntryPoint {
    fun documentRepository(): DocumentRepository
}
```
Fetch it inside the widget's `provideGlance` with `EntryPointAccessors.fromApplication(context, WidgetEntryPoint::class.java)`.

- [ ] **Step 3: Widget receiver + manifest registration**

`PaperlessWidgetReceiver.kt` extends `GlanceAppWidgetReceiver`, overrides `glanceAppWidget = PaperlessWidget()`.

Add to `AndroidManifest.xml` inside `<application>`:
```xml
<receiver android:name=".widget.PaperlessWidgetReceiver" android:exported="false">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data android:name="android.appwidget.provider" android:resource="@xml/paperless_widget_info" />
</receiver>
```
Create `android/app/src/main/res/xml/paperless_widget_info.xml` with standard `appwidget-provider` config (minWidth/minHeight ~250dp, `updatePeriodMillis` 0 since Glance manages its own updates, `resizeMode="horizontal|vertical"`).

- [ ] **Step 4: Build and manually verify**

Run `./gradlew assembleDebug`. Manually add the widget to the emulator home screen (long-press home screen → Widgets → Paperless TeDi) and confirm it renders (empty state if not logged in is acceptable — full data requires a live server).

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/widget android/app/src/main/res/xml/paperless_widget_info.xml android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
git commit -m "feat(android): add home screen widget showing recent documents"
```

---

## Task 15: Background Sync & Notifications (WorkManager)

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/sync/InboxCheckWorker.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/sync/NotificationHelper.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/sync/SyncScheduler.kt`
- Modify: `android/app/build.gradle.kts` — add WorkManager + Hilt-Work dependencies
- Modify: `android/app/src/main/java/de/tedi/paperless/PaperlessApp.kt` — implement `Configuration.Provider` for Hilt worker injection
- Modify: `android/app/src/main/AndroidManifest.xml` — add `POST_NOTIFICATIONS` permission (Android 13+)
- Test: `android/app/src/test/java/de/tedi/paperless/sync/InboxCheckWorkerTest.kt`

- [ ] **Step 1: Add dependencies**

```kotlin
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("androidx.hilt:hilt-work:1.2.0")
    ksp("androidx.hilt:hilt-compiler:1.2.0")
```

- [ ] **Step 2: NotificationHelper — posts a notification with the inbox count**

Creates a notification channel `"inbox_updates"` on first use (`NotificationManager.createNotificationChannel`), then `postInboxNotification(count: Int)` builds and shows a `NotificationCompat.Builder` notification titled "Neue Dokumente" with the count in the body.

- [ ] **Step 3: InboxCheckWorker — HiltWorker querying document count and comparing to last-seen**

```kotlin
@HiltWorker
class InboxCheckWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val documentRepository: DocumentRepository,
    private val notificationHelper: NotificationHelper
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        return try {
            val page = documentRepository.getDocuments(page = 1, pageSize = 1)
            val lastSeen = /* read from a SharedPreferences-backed last-seen count */
            if (page.count > lastSeen) {
                notificationHelper.postInboxNotification(page.count - lastSeen)
            }
            /* persist page.count as new last-seen */
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }
}
```
(Fill in the last-seen persistence using a small dedicated `EncryptedSharedPreferences`-free plain `SharedPreferences` under a new key, e.g. `"sync_prefs"` / `"last_seen_count"` — this doesn't need encryption, it's not a secret.)

- [ ] **Step 4: SyncScheduler — enqueues periodic work (~1h) via WorkManager**

```kotlin
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
```
Call `SyncScheduler.schedule(this)` from `MainActivity.onCreate` (guarded so it only runs once per process, e.g. behind a simple boolean check — WorkManager's `KEEP` policy already makes repeated calls idempotent, so this is just to avoid redundant calls each recomposition).

- [ ] **Step 5: PaperlessApp implements Configuration.Provider for HiltWorkerFactory**

```kotlin
@HiltAndroidApp
class PaperlessApp : Application(), Configuration.Provider {
    @Inject lateinit var workerFactory: HiltWorkerFactory
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()
}
```
Also disable WorkManager's default initializer in the manifest (add a `<provider android:name="androidx.startup.InitializationProvider" ...>` node removing `androidx.work.WorkManagerInitializer` — standard Hilt+WorkManager boilerplate, follow the official androidx.hilt.work setup docs pattern).

- [ ] **Step 6: Write a unit test for the worker's core decision logic**

Extract the "should I notify" comparison (`page.count > lastSeen`) into a small pure function if needed to make it unit-testable without a full `CoroutineWorker` test harness (`androidx.work:work-testing` is heavier-weight; prefer testing the pure logic directly per YAGNI — only add `work-testing` if the worker's control flow can't otherwise be verified).

- [ ] **Step 7: Build, test, verify no crash on launch (permission prompt expected on Android 13+ emulator)**

Run `./gradlew testDebugUnitTest assembleDebug`, install, launch, confirm no crash and (if the emulator is API 33+) a notification-permission system dialog appears — request it via `ActivityCompat.requestPermissions` for `POST_NOTIFICATIONS` if targeting API 33+, gated with a runtime SDK-int check.

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/sync android/app/src/main/java/de/tedi/paperless/PaperlessApp.kt android/app/src/main/AndroidManifest.xml android/app/build.gradle.kts android/app/src/test
git commit -m "feat(android): add background inbox sync with WorkManager notifications"
```

---

## Task 16: Semantic Archive Search

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/search/SemanticSearchRepository.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/AskArchiveViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/search/AskArchiveScreen.kt`
- Test: `android/app/src/test/java/de/tedi/paperless/search/SemanticSearchRepositoryTest.kt`

- [ ] **Step 1: SemanticSearchRepository — ranks documents by keyword overlap as a portable baseline, delegates to AiSummaryRepository for an LLM-composed answer**

There is no direct Android equivalent to Apple's `NLEmbedding` with zero setup cost; rather than adding a heavy on-device embedding model dependency for Phase 2, implement term-overlap ranking (tokenize query and each document's `content`/`title`, score by shared-token count, take top-K) as the retrieval step, then hand the top-K document texts plus the user's question to `AiSummaryRepository`/`CloudSummaryProvider` (extend `AiSummaryProvider` with an `answer(question: String, context: List<String>): String` method) to compose the final natural-language answer. This mirrors the MVP's cloud/on-device split and stays consistent with the existing AI adapter architecture rather than introducing a second, parallel one.

- [ ] **Step 2: Write a test for the ranking function in isolation (pure function, no mocks needed)** — e.g. given 3 documents with varying keyword overlap with a query, assert the ranking order.

- [ ] **Step 3: AskArchiveViewModel + AskArchiveScreen** — a chat-like single-question-single-answer screen (text field + "Fragen" button + scrollable answer area), following the same ViewModel/State/Compose pattern as every other MVP screen.

- [ ] **Step 4: Wire a new "Frage" tab/route into `PaperlessNavHost.kt`** (add `composable("ask") { AskArchiveScreen() }`).

- [ ] **Step 5: Build, test, commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/search android/app/src/main/java/de/tedi/paperless/viewmodel/AskArchiveViewModel.kt android/app/src/main/java/de/tedi/paperless/ui/search android/app/src/main/java/de/tedi/paperless/ui/PaperlessNavHost.kt android/app/src/main/java/de/tedi/paperless/ai android/app/src/test
git commit -m "feat(android): add semantic archive search (keyword ranking + LLM answer)"
```

---

## Task 17: Document Translation

**Files:**
- Modify: `android/app/build.gradle.kts` — add ML Kit Translate
- Create: `android/app/src/main/java/de/tedi/paperless/translation/TranslationRepository.kt`
- Modify: `android/app/src/main/java/de/tedi/paperless/viewmodel/DocumentDetailViewModel.kt` — add translate action + state
- Modify: `android/app/src/main/java/de/tedi/paperless/ui/documents/DocumentDetailScreen.kt` — add a "Übersetzen" button + translated-text display

- [ ] **Step 1: Add dependency**

```kotlin
    implementation("com.google.mlkit:translate:17.0.3")
```

- [ ] **Step 2: TranslationRepository wraps ML Kit's `Translator`** — downloads the target-language model on demand (`DownloadConditions`, require Wi-Fi by default) and exposes `suspend fun translate(text: String, targetLanguageTag: String): String` using `kotlinx.coroutines.tasks.await()` on the ML Kit `Task`.

- [ ] **Step 3: Wire into DocumentDetailViewModel/Screen** — a button next to the document metadata that translates `document.content` to the device's current locale and displays it below the original, with a loading spinner while the model downloads/translates.

- [ ] **Step 4: Build, verify manually in emulator (translation requires the ML Kit model download, which needs network — acceptable to verify only that the button triggers the flow without crashing if the model isn't cached), commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/translation android/app/src/main/java/de/tedi/paperless/viewmodel/DocumentDetailViewModel.kt android/app/src/main/java/de/tedi/paperless/ui/documents/DocumentDetailScreen.kt android/app/build.gradle.kts
git commit -m "feat(android): add on-device document translation via ML Kit"
```

---

## Task 18: AirScan-Style Network Scanner Discovery (eSCL over NSD)

**Files:**
- Create: `android/app/src/main/java/de/tedi/paperless/airscan/NsdScannerDiscovery.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/airscan/EsclClient.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/viewmodel/NetworkScanViewModel.kt`
- Create: `android/app/src/main/java/de/tedi/paperless/ui/upload/NetworkScanScreen.kt`
- Modify: `android/app/src/main/AndroidManifest.xml` — add `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, and (API 33+) `NEARBY_WIFI_DEVICES` permission for NSD

- [ ] **Step 1: NsdScannerDiscovery wraps `android.net.nsd.NsdManager`** — `discoverServices("_uscan._tcp", NsdManager.PROTOCOL_DNS_SD, listener)`, exposes discovered scanners as a `Flow<List<ScannerInfo>>` (host, port, name) via `callbackFlow`.

- [ ] **Step 2: EsclClient implements the eSCL HTTP protocol** — `GET /eSCL/ScannerCapabilities`, `POST /eSCL/ScanJobs` with a minimal ScanSettings XML body, poll the returned job URI, `GET .../NextDocument` to retrieve the scanned page bytes (JPEG or PDF depending on device). Use plain `OkHttpClient` (already a transitive dependency via Retrofit) rather than adding a new HTTP library.

- [ ] **Step 3: NetworkScanViewModel + NetworkScanScreen** — lists discovered scanners (from Step 1's flow), tapping one triggers a scan (Step 2), then feeds the resulting bytes into the existing `UploadViewModel.upload()` flow (reuse Task 9's upload pipeline rather than duplicating it).

- [ ] **Step 4: Wire a "Netzwerkscanner" entry point into `UploadScreen.kt`** (a third button alongside "Dokument scannen" / "Datei auswählen") that navigates to `NetworkScanScreen`.

- [ ] **Step 5: Build and commit** (real-device verification of eSCL against a physical scanner isn't possible in the emulator — acceptable to verify only that NSD discovery starts without crashing and the UI states render correctly with zero discovered devices, which is the expected emulator behavior since there's no real network to discover on).

```bash
git add android/app/src/main/java/de/tedi/paperless/airscan android/app/src/main/java/de/tedi/paperless/viewmodel/NetworkScanViewModel.kt android/app/src/main/java/de/tedi/paperless/ui/upload android/app/src/main/AndroidManifest.xml
git commit -m "feat(android): add network scanner discovery and eSCL scanning"
```

---

## Task 19: Tablet Split-View Layout

**Files:**
- Modify: `android/app/src/main/java/de/tedi/paperless/ui/PaperlessNavHost.kt` — add a width-aware two-pane variant
- Create: `android/app/src/main/java/de/tedi/paperless/ui/documents/DocumentListDetailPane.kt`
- Modify: `android/app/build.gradle.kts` — add `androidx.compose.material3:material3-adaptive-navigation-suite` (or use `WindowSizeClass` from `androidx.compose.material3.windowsizeclass`, already available via the Compose BOM)

- [ ] **Step 1: Compute `WindowSizeClass` in `MainActivity`** via `calculateWindowSizeClass(this)`, pass it down through `PaperlessNavHost(windowSizeClass: WindowSizeClass)`.

- [ ] **Step 2: DocumentListDetailPane** — when `windowSizeClass.widthSizeClass >= WindowWidthSizeClass.Medium`, render `DocumentListScreen` and `DocumentDetailScreen` side-by-side in a `Row` with weighted widths (list gets ~0.4f, detail ~0.6f), keeping a locally-held `selectedDocumentId` state instead of navigating away from the list route. On compact width, fall back to the existing push-navigation behavior (list → detail as a separate route), unchanged from the MVP.

- [ ] **Step 3: Route `PaperlessNavHost`'s `"documents"` composable through `DocumentListDetailPane` instead of directly to `DocumentListScreen`**, passing the size class down.

- [ ] **Step 4: Build and verify at two emulator sizes** — resize the running AVD's window (or launch a tablet AVD, e.g. `sdkmanager "system-images;android-34;google_apis;arm64-v8a"` is already installed; create a second AVD `Pixel_Tablet_API_34` with device profile `pixel_tablet` if not already present via `avdmanager create avd -n Pixel_Tablet_API_34 -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_tablet`) to confirm the two-pane layout activates on the tablet profile and the single-pane behavior is unchanged on the phone profile.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/de/tedi/paperless/ui android/app/build.gradle.kts android/app/src/main/java/de/tedi/paperless/MainActivity.kt
git commit -m "feat(android): add tablet split-view layout for document list/detail"
```

---

## Task 20: Google Assistant App Actions (Siri Shortcuts equivalent)

**Files:**
- Create: `android/app/src/main/res/xml/shortcuts.xml`
- Modify: `android/app/src/main/AndroidManifest.xml` — register `<meta-data android:name="android.app.shortcuts" ...>` and deep-link `<intent-filter>`s on `MainActivity`
- Modify: `android/app/src/main/java/de/tedi/paperless/MainActivity.kt` — handle the shortcut deep-link intents (route to scan/inbox/search/ask)

- [ ] **Step 1: Define static App Shortcuts (long-press app icon) covering the same 4 actions as iOS**: "Dokument scannen" → deep-link `paperlesstedi://scan`, "Posteingang öffnen" → `paperlesstedi://inbox`, "Dokumente durchsuchen" → `paperlesstedi://search`, "Archiv fragen" → `paperlesstedi://ask`. `shortcuts.xml` uses `<shortcut>` elements with `android:shortcutId`, `android:icon`, `android:shortcutShortLabel`, and an `<intent>` targeting `MainActivity` with the appropriate URI.

- [ ] **Step 2: Register a custom URI scheme `paperlesstedi://` on `MainActivity`'s intent-filter** (`android:scheme="paperlesstedi"`), and in `onCreate`/`onNewIntent`, parse `intent.data?.host` (`scan`/`inbox`/`search`/`ask`) into a start-destination override passed to `PaperlessNavHost`.

- [ ] **Step 3: Note on Google Assistant voice invocation**: full "Hey Google, scan a document in Paperless TeDi" voice triggering requires either Android's App Actions with a registered `actions.xml` + Google's Built-In-Intent (BII) shortcuts (e.g. `actions.intent.CREATE_ALARM`-style templates) validated through the Google Play Console's App Actions test tool, which needs a Play Console-linked app listing — not available in local development. Implement the local building block (App Shortcuts + deep links) now, and document in a code comment on `shortcuts.xml` that full Assistant voice-trigger registration is a Play Console publishing-time step, not a code change, so it can't be verified in the emulator alone.

- [ ] **Step 4: Build, manually verify** — long-press the app icon on the emulator's home screen/launcher, confirm the 4 shortcuts appear and each one launches the app at roughly the right screen (exact route correctness depends on Task 16/18 screens existing, which they will by this point in the plan).

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/xml/shortcuts.xml android/app/src/main/AndroidManifest.xml android/app/src/main/java/de/tedi/paperless/MainActivity.kt
git commit -m "feat(android): add app shortcuts and deep links (Assistant integration groundwork)"
```

---

## Task 21: Final Full-Suite Verification

**Files:** none (verification only)

- [ ] **Step 1:** `./gradlew clean testDebugUnitTest assembleDebug` — `BUILD SUCCESSFUL`, all tests pass.
- [ ] **Step 2:** Install on both the phone AVD (`Pixel_API_34`) and, if created in Task 19, the tablet AVD. Launch on each, confirm no fatal crash via `adb logcat -d "*:E"`.
- [ ] **Step 3:** Report back to the user: full feature list implemented, any features that are stubs pending external constraints (on-device Gemini Nano needs minSdk 31 or a compatible SDK release; Assistant voice-trigger needs Play Console publishing), and how to test each new feature manually against a real Paperless-ngx server.
