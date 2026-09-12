import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette
    let onLogout: () -> Void

    @AppStorage("pageSize") private var pageSize = 25
    @AppStorage("rowShowCorrespondent") private var rowShowCorrespondent = true
    @AppStorage("rowShowDate") private var rowShowDate = true
    @AppStorage("rowShowType") private var rowShowType = false
    @AppStorage("rowShowASN") private var rowShowASN = false
    @AppStorage("rowShowAdded") private var rowShowAdded = false
    @AppStorage("deadlineRadarEnabled") private var deadlineRadarEnabled = false
    @AppStorage("deadlineFieldId") private var deadlineFieldId = 0
    @AppStorage("duplicateCheckEnabled") private var duplicateCheckEnabled = true
    @State private var archiveIndexCount: Int? = nil
    @AppStorage("appLanguage") private var appLanguage = ""
    @AppStorage("aiEnabled") private var aiEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("batchScanEnabled") private var batchScanEnabled = true
    @AppStorage("translationEnabled") private var translationEnabled = true
    @State private var showAskArchive = false
    @State private var stats: PaperlessStatistics? = nil
    @State private var spotlightRebuild: SpotlightRebuild = .idle
    @State private var widgetEnabled: Bool = UserDefaults(suiteName: "group.com.Thomas.paperless")?.bool(forKey: "widget_enabled") ?? true
    @State private var widgetMode: String = UserDefaults(suiteName: "group.com.Thomas.paperless")?.string(forKey: "widget_mode") ?? "documents"
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Dashboard")) {
                    HStack {
                        Image(systemName: "internaldrive.fill").foregroundColor(.gray)
                        Text("App Speicher")
                        Spacer()
                        Text(store.storageSize).bold()
                    }
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            DashboardItem(title: "Posteingang", value: "\(stats?.documentsInbox ?? 0)", icon: "tray.full.fill", color: .pink)
                            DashboardItem(title: "Dokumente", value: formatNumber(stats?.documentsTotal), icon: "doc.text.fill", color: .blue)
                        }
                        HStack(spacing: 12) {
                            DashboardItem(title: "Zeichen", value: formatNumber(stats?.characterCount), icon: "text.alignleft", color: .purple)
                            DashboardItem(title: "Letzte ASN", value: "\(store.documents.compactMap { $0.archiveSerialNumber }.max() ?? 0)", icon: "number", color: .orange)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Konten") {
                    NavigationLink(destination: AccountsView()) {
                        Label("Konten verwalten", systemImage: "person.2")
                    }
                }

                Section("Verwaltung") {
                    NavigationLink(destination: OfflineDocsView()) {
                        HStack {
                            Label("Offline Dateien", systemImage: "arrow.down.doc")
                            Spacer()
                            Text("\(store.cachedCount)").foregroundColor(.secondary)
                        }
                    }
                    NavigationLink(destination: TagListView()) { Label("Tags verwalten", systemImage: "tag") }
                    NavigationLink(destination: CorrespondentListView()) { Label("Sender verwalten", systemImage: "person.2") }
                    NavigationLink(destination: DocTypeListView()) { Label("Typen verwalten", systemImage: "doc") }
                    NavigationLink(destination: TrashView()) { Label("Papierkorb", systemImage: "trash") }
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
                    .foregroundColor(.blue)
                    .disabled(spotlightRebuild == .running)

                    if case .done(let result) = spotlightRebuild {
                        Text(spotlightResultText(result))
                            .font(.caption)
                            .foregroundColor(result.errorMessage == nil ? .secondary : .red)
                    }
                }

                Section("Status") {
                    NavigationLink("Warteschlange", destination: PendingQueueView())
                    if store.isDownloadingAll {
                        VStack(alignment: .leading) {
                            Text(store.downloadStatusText).font(.caption)
                            ProgressView(value: store.downloadProgress)
                        }
                        Button("Stop") { store.stopDownload() }.foregroundColor(.red)
                    } else {
                        Button("Alle Dokumente herunterladen") { store.startFullDownload() }
                    }
                }

                Section {
                    Toggle("Sender", isOn: $rowShowCorrespondent)
                    Toggle("Typ", isOn: $rowShowType)
                    Toggle("Belegdatum", isOn: $rowShowDate)
                    Toggle("Hinzugefügt am", isOn: $rowShowAdded)
                    Toggle("ASN", isOn: $rowShowASN)
                } header: {
                    Text("Angaben in der Liste")
                } footer: {
                    Text("Gilt für die Listenansicht. Bei einer Suche steht an dieser Stelle "
                         + "der Textausschnitt mit dem Suchbegriff.")
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
                    Text("Ohne Index durchsucht die Frage nur die geladenen Dokumente. Der "
                         + "Aufbau liest einmal das ganze Archiv und hält sich danach von "
                         + "selbst aktuell.")
                }

                Section {
                    Toggle("Dublettenprüfung beim Import", isOn: $duplicateCheckEnabled)
                } footer: {
                    Text("Vergleicht vor dem Hochladen Belegnummer, Betrag und Datum mit den "
                         + "geladenen Dokumenten. Warnt nur — hochladen lässt sich trotzdem.")
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
                    Text("Findet Zahlungsziele, Kündigungs- und Garantiefristen im Text — nur "
                         + "wenn ein eindeutiges Schlüsselwort daneben steht. Gespeichert wird "
                         + "erst, was du bestätigst; die Frist landet in einem Datumsfeld auf "
                         + "dem Server.")
                }

                Section("Laden") {
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

                Section {
                    Toggle("KI-Funktionen (Apple Intelligence)", isOn: $aiEnabled)
                    Button {
                        showAskArchive = true
                    } label: {
                        Label("Archiv fragen", systemImage: "sparkles")
                    }
                    .disabled(!aiEnabled)
                    Toggle("Stapel-Trennung beim Scannen", isOn: $batchScanEnabled)
                    Toggle("Übersetzen-Aktion in Dokumenten", isOn: $translationEnabled)
                } header: {
                    Text("Intelligenz")
                } footer: {
                    Text(AIService.shared.modelAvailable
                         ? "Zusammenfassungen, Auto-Tagging und Archiv-Fragen laufen on-device."
                         : "Apple Intelligence ist auf diesem Gerät nicht verfügbar. Auto-Tagging nutzt weiterhin die Texterkennung.")
                }

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

                Section("Darstellung") {
                    NavigationLink(destination: AppearanceView()) {
                        Label("Farbthema & Darstellung", systemImage: "paintpalette")
                    }
                    Picker("Sprache", selection: $appLanguage) {
                        Text("🌐 Systemsprache").tag("")
                        Text("🇩🇪 Deutsch").tag("de")
                        Text("🇬🇧 English").tag("en")
                        Text("🇫🇷 Français").tag("fr")
                        Text("🇪🇸 Español").tag("es")
                        Text("🇮🇹 Italiano").tag("it")
                    }
                }

                Section {
                    Button {
                        openURL(ReviewRequestService.shared.appStoreWriteReviewURL())
                    } label: {
                        Label("App bewerten", systemImage: "star")
                    }
                    NavigationLink(destination: ChangelogView()) {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink(destination: SupportView()) {
                        Label("Unterstützung", systemImage: "heart")
                    }
                    Button("Abmelden", role: .destructive) {
                        store.clearLocalData()
                        onLogout()
                    }
                    HStack {
                        Spacer()
                        Text("v\(AppConstants.appVersion)").font(.caption).foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
            .themedSurface(palette)
            .navigationTitle("Einstellungen")
            .onAppear {
                Task { stats = await store.fetchStatistics() }
            }
            .sheet(isPresented: $showAskArchive) {
                AskArchiveView()
            }
        }
    }

    private func formatNumber(_ n: Int?) -> String {
        guard let n = n else { return "0" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Stand des Spotlight-Neuaufbaus. Der Lauf kann bei großen Archiven ein paar Sekunden
    /// dauern — ohne Rückmeldung sieht der Knopf aus, als täte er nichts.
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

/// „Unterstützung": Hinweis, dass die App kostenlos ist, plus PayPal-Trinkgeld.
struct SupportView: View {
    @Environment(\.palette) private var palette

    /// PayPal.Me-Link des Entwicklers.
    static let payPalURL = URL(string: "https://paypal.me/tdillmann87")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 52))
                    .foregroundColor(palette.accent)
                    .padding(.top, 32)

                Text("Paperless 24 ist kostenlos")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Ich entwickle Paperless 24 in meiner Freizeit und stelle die App kostenlos zur Verfügung. Wenn sie dir hilft, freue ich mich über ein kleines Trinkgeld – ganz freiwillig und in beliebiger Höhe.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: Self.payPalURL) {
                    Label("Mit PayPal ein Trinkgeld geben", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Du wirst dafür zu PayPal weitergeleitet. Vielen Dank für deine Unterstützung! 🙏")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Unterstützung")
        .navigationBarTitleDisplayMode(.inline)
    }
}
