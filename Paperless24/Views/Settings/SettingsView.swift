import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    let onLogout: () -> Void

    @AppStorage("appearanceMode") private var appearanceMode = 0
    @AppStorage("pageSize") private var pageSize = 25
    @AppStorage("appLanguage") private var appLanguage = ""
    @AppStorage("gridItemSize") private var gridItemSize: Double = 130
    @AppStorage("aiEnabled") private var aiEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("batchScanEnabled") private var batchScanEnabled = true
    @AppStorage("translationEnabled") private var translationEnabled = true
    @State private var showAskArchive = false
    @State private var stats: PaperlessStatistics? = nil
    @State private var widgetEnabled: Bool = UserDefaults(suiteName: "group.com.Thomas.paperless")?.bool(forKey: "widget_enabled") ?? true
    @State private var widgetMode: String = UserDefaults(suiteName: "group.com.Thomas.paperless")?.string(forKey: "widget_mode") ?? "documents"

    var body: some View {
        NavigationView {
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
                    Button("Spotlight Index neu erstellen") {
                        store.clearSpotlightIndex()
                        store.indexDocumentsForSpotlight()
                    }
                    .foregroundColor(.blue)
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
                    VStack(alignment: .leading) {
                        Text("Kachelgröße").font(.subheadline)
                        Slider(value: $gridItemSize, in: 90...260, step: 10)
                        Text("\(Int(gridItemSize)) pt").font(.caption).foregroundColor(.secondary)
                    }
                    Picker("Sprache", selection: $appLanguage) {
                        Text("🌐 Systemsprache").tag("")
                        Text("🇩🇪 Deutsch").tag("de")
                        Text("🇬🇧 English").tag("en")
                        Text("🇫🇷 Français").tag("fr")
                        Text("🇪🇸 Español").tag("es")
                        Text("🇮🇹 Italiano").tag("it")
                    }
                    Picker("Design", selection: $appearanceMode) {
                        Text("Auto").tag(0)
                        Text("Hell").tag(1)
                        Text("Dunkel").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    NavigationLink(destination: ChangelogView()) {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
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
}
