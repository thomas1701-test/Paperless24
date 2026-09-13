import SwiftUI
import WidgetKit
import LocalAuthentication

// Die Kategorien der Einstellungen. Jede Seite bündelt, was inhaltlich zusammengehört —
// vorher standen alle Schalter auf einer einzigen, sehr langen Seite.

/// Zeile einer Kategorie: farbiges Symbol wie in den iOS-Einstellungen, Titel und eine kurze
/// Zeile darunter, was sich dahinter verbirgt.
struct SettingsCategoryLabel: View {
    private let title: LocalizedStringKey
    private let subtitle: Text?
    private let systemImage: String
    private let color: Color
    private let badge: Int?

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String,
         color: Color, badge: Int? = nil) {
        self.title = title
        self.subtitle = subtitle.map { Text($0) }
        self.systemImage = systemImage
        self.color = color
        self.badge = badge
    }

    /// Für Werte, die nicht übersetzt werden (Benutzername, Rechner).
    init(title: LocalizedStringKey, verbatimSubtitle: String?, systemImage: String, color: Color) {
        self.title = title
        self.subtitle = verbatimSubtitle.map { Text(verbatim: $0) }
        self.systemImage = systemImage
        self.color = color
        self.badge = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    subtitle.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Archiv verwalten

struct LibrarySettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Section("Stammdaten") {
                NavigationLink(destination: TagListView()) { Label("Tags verwalten", systemImage: "tag") }
                NavigationLink(destination: CorrespondentListView()) { Label("Sender verwalten", systemImage: "person.2") }
                NavigationLink(destination: DocTypeListView()) { Label("Typen verwalten", systemImage: "doc") }
                NavigationLink(destination: CustomFieldListView()) {
                    Label("Eigene Felder", systemImage: "character.textbox")
                }
            }
            Section("Auswertungen") {
                NavigationLink(destination: StatisticsView()) {
                    Label("Statistik", systemImage: "chart.bar")
                }
                NavigationLink(destination: SeriesView()) {
                    Label("Regelmäßiges", systemImage: "repeat")
                }
            }
            Section {
                NavigationLink(destination: TrashView()) { Label("Papierkorb", systemImage: "trash") }
            }
        }
        .themedSurface(palette)
        .navigationTitle("Archiv verwalten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Offline & Laden

struct OfflineSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette
    @AppStorage("pageSize") private var pageSize = 25

    var body: some View {
        Form {
            Section {
                Picker("Dokumente beim Start", selection: $pageSize) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                    Text("2000").tag(2000)
                    Text("Alles").tag(100000)
                }
            } header: {
                Text("Laden")
            } footer: {
                Text("Weitere Dokumente lädt die Liste beim Scrollen nach.")
            }

            Section {
                NavigationLink(destination: OfflineDocsView()) {
                    HStack {
                        Label("Offline Dateien", systemImage: "arrow.down.doc")
                        Spacer()
                        Text("\(store.cachedCount)").foregroundColor(.secondary)
                    }
                }
                if store.isDownloadingAll {
                    VStack(alignment: .leading) {
                        Text(store.downloadStatusText).font(.caption)
                        ProgressView(value: store.downloadProgress)
                    }
                    Button("Stop") { store.stopDownload() }.foregroundColor(.red)
                } else {
                    Button("Alle Dokumente herunterladen") { store.startFullDownload() }
                }
            } header: {
                Text("Offline-Betrieb")
            } footer: {
                Text("Heruntergeladene Dokumente lassen sich auch ohne Verbindung zum Server öffnen.")
            }

            Section {
                NavigationLink(destination: PendingQueueView()) {
                    HStack {
                        Label("Warteschlange", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        let count = store.pendingUploads.count + store.pendingEdits.count
                        if count > 0 { Text("\(count)").foregroundColor(.secondary) }
                    }
                }
            } footer: {
                Text("Uploads und Änderungen ohne Verbindung warten hier und gehen raus, sobald der Server erreichbar ist.")
            }
        }
        .themedSurface(palette)
        .navigationTitle("Offline & Laden")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - KI & Automatik

struct IntelligenceSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @AppStorage("aiEnabled") private var aiEnabled = true
    @AppStorage("batchScanEnabled") private var batchScanEnabled = true
    @AppStorage("translationEnabled") private var translationEnabled = true
    @AppStorage("duplicateCheckEnabled") private var duplicateCheckEnabled = true
    @AppStorage("deadlineRadarEnabled") private var deadlineRadarEnabled = false
    @AppStorage("deadlineFieldId") private var deadlineFieldId = 0
    @State private var archiveIndexCount: Int? = nil
    @State private var showAskArchive = false

    var body: some View {
        Form {
            Section {
                Toggle("KI-Funktionen (Apple Intelligence)", isOn: $aiEnabled)
                Button {
                    showAskArchive = true
                } label: {
                    Label("Archiv fragen", systemImage: "sparkles")
                }
                .disabled(!aiEnabled)
                Toggle("Übersetzen-Aktion in Dokumenten", isOn: $translationEnabled)
            } header: {
                Text("Intelligenz")
            } footer: {
                Text(AIService.shared.modelAvailable
                     ? "Zusammenfassungen, Auto-Tagging und Archiv-Fragen laufen on-device."
                     : "Apple Intelligence ist auf diesem Gerät nicht verfügbar. Auto-Tagging nutzt weiterhin die Texterkennung.")
            }

            Section {
                HStack {
                    Text("Im Index")
                    Spacer()
                    Text(archiveIndexCount.map { "\($0) Dokumente" } ?? "—")
                        .foregroundColor(.secondary)
                }
                if store.isBuildingArchiveIndex {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: store.archiveIndexProgress)
                        Text(store.archiveIndexStatus ?? "").font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Index über das ganze Archiv aufbauen") {
                        Task {
                            await store.buildFullArchiveIndex()
                            archiveIndexCount = await store.archiveIndexCount()
                        }
                    }
                    if let status = store.archiveIndexStatus {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                    if (archiveIndexCount ?? 0) > 0 {
                        Button("Index leeren", role: .destructive) {
                            Task {
                                await store.clearArchiveIndex()
                                archiveIndexCount = await store.archiveIndexCount()
                            }
                        }
                    }
                }
            } header: {
                Text("Archiv fragen")
            } footer: {
                Text("Ohne Index durchsucht die Frage nur die geladenen Dokumente. Der Aufbau liest einmal das ganze Archiv und hält sich danach von selbst aktuell.")
            }

            Section {
                NavigationLink(destination: UploadRulesView()) {
                    Label("Import-Regeln", systemImage: "wand.and.stars")
                }
                Toggle("Stapel-Trennung beim Scannen", isOn: $batchScanEnabled)
                Toggle("Dublettenprüfung beim Import", isOn: $duplicateCheckEnabled)
            } header: {
                Text("Scannen & Importieren")
            } footer: {
                Text("Die Dublettenprüfung vergleicht vor dem Hochladen Belegnummer, Betrag und Datum mit den geladenen Dokumenten. Warnt nur — hochladen lässt sich trotzdem.")
            }

            Section {
                Toggle("Fristen-Radar", isOn: $deadlineRadarEnabled)
                if deadlineRadarEnabled {
                    NavigationLink(destination: DeadlinesView()) {
                        Label("Was steht an", systemImage: "calendar.badge.clock")
                    }
                    Picker("Feld für Fristen", selection: $deadlineFieldId) {
                        Text("Automatisch").tag(0)
                        ForEach(store.allCustomFields.filter { $0.type == .date }) { field in
                            Text(field.safeName).tag(field.id)
                        }
                    }
                }
            } header: {
                Text("Fristen")
            } footer: {
                Text("Findet Zahlungsziele, Kündigungs- und Garantiefristen im Text — nur wenn ein eindeutiges Schlüsselwort daneben steht. Gespeichert wird erst, was du bestätigst; die Frist landet in einem Datumsfeld auf dem Server.")
            }
        }
        .themedSurface(palette)
        .navigationTitle("KI & Automatik")
        .navigationBarTitleDisplayMode(.inline)
        .task { archiveIndexCount = await store.archiveIndexCount() }
        .sheet(isPresented: $showAskArchive) {
            AskArchiveView()
        }
    }
}

// MARK: - Mitteilungen & Widget

struct NotificationSettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var widgetEnabled: Bool = UserDefaults(suiteName: "group.com.Thomas.paperless")?.object(forKey: "widget_enabled") as? Bool ?? true
    @State private var widgetMode: String = UserDefaults(suiteName: "group.com.Thomas.paperless")?.string(forKey: "widget_mode") ?? "documents"

    var body: some View {
        Form {
            Section("Benachrichtigungen") {
                Toggle("Neue Dokumente melden", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        if on {
                            Task {
                                _ = await NotificationService.requestAuthorization()
                                NotificationService.scheduleRefresh()
                            }
                        }
                    }
            }

            Section("Widget") {
                Toggle("Widget aktiv", isOn: $widgetEnabled)
                    .onChange(of: widgetEnabled) { _, val in
                        UserDefaults(suiteName: "group.com.Thomas.paperless")?.set(val, forKey: "widget_enabled")
                        store.updateWidget()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                if widgetEnabled {
                    Picker("Anzeige", selection: $widgetMode) {
                        Text("Letzte Dokumente").tag("documents")
                        Text("Übersicht").tag("overview")
                    }
                    .onChange(of: widgetMode) { _, val in
                        UserDefaults(suiteName: "group.com.Thomas.paperless")?.set(val, forKey: "widget_mode")
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        }
        .themedSurface(palette)
        .navigationTitle("Mitteilungen & Widget")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Datenschutz & Spotlight

struct PrivacySettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette
    @Environment(\.locale) private var locale

    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("spotlightEnabled") private var spotlightEnabled = true
    @AppStorage("spotlightFullText") private var spotlightFullText = true
    @State private var spotlightRebuild: SpotlightRebuild = .idle
    @State private var authError: String? = nil

    var body: some View {
        Form {
            Section {
                Toggle("App-Sperre (Face ID / Code)", isOn: Binding(
                    get: { useFaceID },
                    set: { requestAppLockChange(to: $0) }
                ))
            } footer: {
                Text("Fragt beim Öffnen und nach einer Minute im Hintergrund nach Face ID oder dem Gerätecode.")
            }

            Section {
                Toggle("In Spotlight aufnehmen", isOn: $spotlightEnabled)
                    .onChange(of: spotlightEnabled) { _, _ in store.applySpotlightSettings() }
                Toggle("Volltext durchsuchbar", isOn: Binding(
                    get: { spotlightFullText && !useFaceID },
                    set: { spotlightFullText = $0 }
                ))
                .disabled(!spotlightEnabled || useFaceID)
                .onChange(of: spotlightFullText) { _, _ in store.applySpotlightSettings() }

                if spotlightEnabled {
                    Button {
                        Task {
                            spotlightRebuild = .running
                            spotlightRebuild = .done(await store.rebuildSpotlightIndex())
                        }
                    } label: {
                        HStack {
                            Text("Spotlight Index neu erstellen")
                            Spacer()
                            if spotlightRebuild == .running { ProgressView() }
                        }
                    }
                    .disabled(spotlightRebuild == .running)

                    if case .done(let result) = spotlightRebuild {
                        Text(spotlightResultText(result))
                            .font(.caption)
                            .foregroundColor(result.errorMessage == nil ? .secondary : .red)
                    }
                }
            } header: {
                Text("Systemsuche")
            } footer: {
                Text(useFaceID
                     ? "Bei aktiver App-Sperre stehen nur Titel, Sender und Tags in Spotlight — der erkannte Text bleibt in der App."
                     : "Mit Volltext findet die Systemsuche Dokumente auch über ihren Inhalt. Der Text ist dann für jeden sichtbar, der das Gerät entsperrt hat.")
            }
        }
        .themedSurface(palette)
        .navigationTitle("Datenschutz & Spotlight")
        .navigationBarTitleDisplayMode(.inline)
        .alert("App-Sperre", isPresented: Binding(
            get: { authError != nil },
            set: { if !$0 { authError = nil } }
        )) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            Text(authError ?? "")
        }
    }

    /// Ein- und Ausschalten verlangt den Gerätebesitzer: Sonst schaltet jeder, der das
    /// entsperrte Telefon kurz in der Hand hat, die Sperre ab.
    private func requestAppLockChange(to newValue: Bool) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = String(localized: "Auf diesem Gerät ist kein Code eingerichtet. Ohne Gerätecode gibt es keine App-Sperre.", locale: locale)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: String(localized: "biometric_reason", locale: locale)) { success, _ in
            DispatchQueue.main.async {
                guard success else { return }
                useFaceID = newValue
                // Der Volltext richtet sich nach der Sperre — der Index muss nachziehen.
                store.applySpotlightSettings()
            }
        }
    }

    private enum SpotlightRebuild: Equatable {
        case idle
        case running
        case done(AppStore.SpotlightIndexResult)
    }

    private func spotlightResultText(_ result: AppStore.SpotlightIndexResult) -> String {
        guard let message = result.errorMessage else {
            return String(format: String(localized: "Fertig — %lld Dokumente im Index"), result.indexed)
        }
        return String(format: String(localized: "%1$lld indiziert, %2$lld abgelehnt: %3$@"),
                      result.indexed, result.rejected, message)
    }
}

// MARK: - Hilfe & Info

struct AboutSettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                NavigationLink(destination: DiagnosticsView()) {
                    Label("Diagnose", systemImage: "stethoscope")
                }
                NavigationLink(destination: ChangelogView()) {
                    Label("Changelog", systemImage: "list.bullet.rectangle")
                }
            }
            Section {
                Button {
                    openURL(ReviewRequestService.shared.appStoreWriteReviewURL())
                } label: {
                    Label("App bewerten", systemImage: "star")
                }
                NavigationLink(destination: SupportView()) {
                    Label("Unterstützung", systemImage: "heart")
                }
            } footer: {
                Text("v\(AppConstants.appVersion)")
            }
        }
        .themedSurface(palette)
        .navigationTitle("Hilfe & Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}
