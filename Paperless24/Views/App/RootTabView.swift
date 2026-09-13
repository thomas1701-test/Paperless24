import SwiftUI
import StoreKit

struct RootTabView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    let onLogout: () -> Void

    @State private var selectedTab = 0
    @State private var showScanner = false
    @State private var showAskArchive = false
    @State private var reviewPending = false

    var body: some View {
        TabView(selection: $selectedTab) {
            MainDocView()
                .tabItem { Label("Dokumente", systemImage: "doc.text") }
                .tag(0)

            InboxView()
                .tabItem { Label("Posteingang", systemImage: "tray.fill") }
                .tag(1)
                .badge(store.inboxCount)

            Color.clear
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
                .tag(2)

            // SettingsView bringt eigenen NavigationStack mit — kein zweiter Wrapper,
            // sonst doppelte Navigation Bar auf iPad.
            SettingsView(onLogout: onLogout)
                .tabItem { Label("Einstellungen", systemImage: "gear") }
                .tag(3)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == 2 { showScanner = true; selectedTab = 0 }
        }
        .onChange(of: store.widgetOpenDocId) { _, id in
            if id != nil { selectedTab = 0 }
        }
        .onChange(of: store.pickerCallbackURL) { _, url in
            if url != nil { selectedTab = 0 }
        }
        .onChange(of: store.requestScan) { _, req in
            if req { store.requestScan = false; showScanner = true }
        }
        .onChange(of: store.requestInbox) { _, req in
            if req { store.requestInbox = false; selectedTab = 1 }
        }
        .onChange(of: store.pendingSearch) { _, q in
            if q != nil { selectedTab = 0 }   // MainDocView übernimmt die eigentliche Suche
        }
        .onChange(of: store.requestAskArchive) { _, req in
            if req { store.requestAskArchive = false; showAskArchive = true }
        }
        .onChange(of: store.shouldRequestReview) { _, req in
            if req {
                store.shouldRequestReview = false
                guard !reviewPending else { return }
                reviewPending = true
                Task { await promptForReviewWhenIdle() }
            }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView(isPresented: $showScanner) { data in
                store.handleImportData(data: data, filename: "Scan_\(Date().timeIntervalSince1970).pdf")
            }
        }
        .sheet(isPresented: $showAskArchive) {
            AskArchiveView()
        }
    }

    /// iOS unterdrückt den Bewertungsdialog stillschweigend, solange ein Sheet
    /// auf- oder zugeht oder die Szene nicht aktiv ist — `recordPrompt()` würde
    /// den Versuch aber trotzdem verbrennen und die Version für immer sperren.
    /// Darum: warten, bis die Oberfläche ruhig ist, und erst dann fragen.
    /// Nach ~20 s aufgeben, der nächste positive Moment versucht es erneut.
    @MainActor
    private func promptForReviewWhenIdle() async {
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard reviewPending else { return }
            if scenePhase == .active && !showScanner && !showAskArchive {
                reviewPending = false
                ReviewRequestService.shared.recordPrompt()
                requestReview()
                return
            }
        }
        reviewPending = false
    }
}
