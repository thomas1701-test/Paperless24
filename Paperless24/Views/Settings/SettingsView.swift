import SwiftUI

/// Einstiegsseite der Einstellungen: Überblick, Konto und die Kategorien. Die eigentlichen
/// Schalter liegen eine Ebene tiefer (`SettingsCategoryViews.swift`) — vorher standen über
/// dreißig Einträge untereinander auf einer Seite.
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette
    let onLogout: () -> Void

    @State private var stats: PaperlessStatistics? = nil
    @State private var showLogoutConfirm = false

    private var queueCount: Int { store.pendingUploads.count + store.pendingEdits.count }

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

                // Nur wenn etwas wartet — dann aber gleich oben, nicht versteckt in einer Kategorie.
                if queueCount > 0 {
                    Section {
                        NavigationLink(destination: PendingQueueView()) {
                            SettingsCategoryLabel(
                                title: "Warteschlange",
                                subtitle: "Noch nicht an den Server übertragen",
                                systemImage: "clock.arrow.circlepath",
                                color: .orange,
                                badge: queueCount
                            )
                        }
                    }
                }

                Section("Konto") {
                    NavigationLink(destination: AccountsView()) {
                        SettingsCategoryLabel(
                            title: "Konten verwalten",
                            verbatimSubtitle: store.activeAccount.map { "\($0.username) · \(Self.host(of: $0.serverUrl))" },
                            systemImage: "person.2.fill",
                            color: .blue
                        )
                    }
                    NavigationLink(destination: ServerAccessView(server: PaperlessAPI.normalizedBase(store.serverUrl))) {
                        SettingsCategoryLabel(
                            title: "Serverzugang",
                            subtitle: "Proxy-Kopfzeilen, Client-Zertifikat",
                            systemImage: "lock.shield.fill",
                            color: .teal
                        )
                    }
                }

                Section {
                    NavigationLink(destination: LibrarySettingsView()) {
                        SettingsCategoryLabel(
                            title: "Archiv verwalten",
                            subtitle: "Tags, Sender, Typen, Felder, Papierkorb",
                            systemImage: "archivebox.fill",
                            color: .brown
                        )
                    }
                    NavigationLink(destination: OfflineSettingsView()) {
                        SettingsCategoryLabel(
                            title: "Offline & Laden",
                            subtitle: "Offline-Dateien, Download, Warteschlange",
                            systemImage: "arrow.down.circle.fill",
                            color: .green
                        )
                    }
                    NavigationLink(destination: IntelligenceSettingsView()) {
                        SettingsCategoryLabel(
                            title: "KI & Automatik",
                            subtitle: "Apple Intelligence, Import-Regeln, Fristen",
                            systemImage: "sparkles",
                            color: .purple
                        )
                    }
                    NavigationLink(destination: AppearanceView()) {
                        SettingsCategoryLabel(
                            title: "Darstellung",
                            subtitle: "Farbthema, Liste, Sprache",
                            systemImage: "paintpalette.fill",
                            color: .pink
                        )
                    }
                    NavigationLink(destination: NotificationSettingsView()) {
                        SettingsCategoryLabel(
                            title: "Mitteilungen & Widget",
                            systemImage: "bell.badge.fill",
                            color: .red
                        )
                    }
                    NavigationLink(destination: PrivacySettingsView()) {
                        SettingsCategoryLabel(
                            title: "Datenschutz & Spotlight",
                            subtitle: "App-Sperre, Systemsuche",
                            systemImage: "hand.raised.fill",
                            color: .indigo
                        )
                    }
                }

                Section {
                    NavigationLink(destination: AboutSettingsView()) {
                        SettingsCategoryLabel(
                            title: "Hilfe & Info",
                            subtitle: "Diagnose, Changelog, Unterstützung",
                            systemImage: "questionmark.circle.fill",
                            color: .gray
                        )
                    }
                }

                Section {
                    Button("Abmelden", role: .destructive) { showLogoutConfirm = true }
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
            // Abmelden löscht Warteschlange, Offline-Dateien und Zugangsdaten auf dem Gerät —
            // das darf kein Fehltipp auslösen.
            .confirmationDialog("Abmelden?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) {
                    store.clearLocalData()
                    onLogout()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(queueCount > 0
                     ? "Alle Konten werden samt Offline-Dateien und Zugangsdaten vom Gerät entfernt. Noch nicht übertragene Uploads und Änderungen gehen verloren."
                     : "Alle Konten werden samt Offline-Dateien und Zugangsdaten vom Gerät entfernt.")
            }
        }
    }

    private func formatNumber(_ n: Int?) -> String {
        guard let n = n else { return "0" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Nur der Rechnername — die volle Adresse ist in der Zeile zu lang.
    static func host(of serverUrl: String) -> String {
        URL(string: PaperlessAPI.normalizedBase(serverUrl))?.host ?? serverUrl
    }
}

/// „Unterstützung": Dank für den Kauf und Wege, die App weiterzubringen, die nichts kosten.
///
/// Bis 2.2.0 stand hier „Paperless 24 ist kostenlos" mit PayPal-Trinkgeld. Die App wird
/// inzwischen über den Store-Preis verkauft — der Text stimmte nicht mehr, und ein externer
/// Trinkgeld-Link an den Entwickler ist in einer Kauf-App ein Ablehnungsgrund (Richtlinie 3.1.1).
struct SupportView: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    /// Store-Seite der App zum Weiterempfehlen.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(AppConstants.appStoreId)")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(palette.accent)
                    .padding(.top, 32)

                Text("Danke für deine Unterstützung")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Mit dem Kauf von Paperless 24 unterstützt du die Weiterentwicklung der App. Wenn sie dir gefällt, hilft eine Bewertung im App Store oder eine Empfehlung am meisten – so finden andere Paperless-Nutzer die App.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    Button {
                        openURL(ReviewRequestService.shared.appStoreWriteReviewURL())
                    } label: {
                        Label("App bewerten", systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: Self.appStoreURL) {
                        Label("App weiterempfehlen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle("Unterstützung")
        .navigationBarTitleDisplayMode(.inline)
    }
}
