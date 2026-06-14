import SwiftUI
import StoreKit

struct RootTabView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.requestReview) private var requestReview
    let onLogout: () -> Void

    @State private var selectedTab = 0
    @State private var showScanner = false
    @State private var showAskArchive = false

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

            NavigationStack {
                SettingsView(onLogout: onLogout)
            }
            .tabItem { Label("Einstellungen", systemImage: "gear") }
            .tag(3)
        }
        .onChange(of: selectedTab) { tab in
            if tab == 2 { showScanner = true; selectedTab = 0 }
        }
        .onChange(of: store.widgetOpenDocId) { id in
            if id != nil { selectedTab = 0 }
        }
        .onChange(of: store.pickerCallbackURL) { url in
            if url != nil { selectedTab = 0 }
        }
        .onChange(of: store.requestScan) { req in
            if req { store.requestScan = false; showScanner = true }
        }
        .onChange(of: store.requestInbox) { req in
            if req { store.requestInbox = false; selectedTab = 1 }
        }
        .onChange(of: store.pendingSearch) { q in
            if q != nil { selectedTab = 0 }   // MainDocView übernimmt die eigentliche Suche
        }
        .onChange(of: store.requestAskArchive) { req in
            if req { store.requestAskArchive = false; showAskArchive = true }
        }
        .onChange(of: store.shouldRequestReview) { req in
            if req {
                store.shouldRequestReview = false
                ReviewRequestService.shared.recordPrompt()
                requestReview()
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
}
