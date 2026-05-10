import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Binding var isPresented: Bool
    let onLogout: () -> Void

    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var stats: PaperlessStatistics? = nil

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

                Section {
                    NavigationLink(destination: ChangelogView()) {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
                    Picker("Design", selection: $appearanceMode) {
                        Text("Auto").tag(0)
                        Text("Hell").tag(1)
                        Text("Dunkel").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Button("Abmelden", role: .destructive) {
                        isPresented = false
                        store.clearLocalData()
                        KeychainService.deleteToken(for: store.serverUrl)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { isPresented = false }
                }
            }
            .onAppear {
                Task { stats = await store.fetchStatistics() }
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
