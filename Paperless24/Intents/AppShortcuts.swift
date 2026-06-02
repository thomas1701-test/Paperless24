import AppIntents

// MARK: - Intents

struct ScanDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Dokument scannen"
    static var description = IntentDescription("Öffnet den Scanner, um ein neues Dokument aufzunehmen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared?.requestScan = true
        return .result()
    }
}

struct OpenInboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Posteingang öffnen"
    static var description = IntentDescription("Zeigt die noch nicht bearbeiteten Dokumente.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared?.requestInbox = true
        return .result()
    }
}

struct SearchDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Dokumente suchen"
    static var description = IntentDescription("Sucht in Paperless nach Dokumenten.")
    static var openAppWhenRun = true

    @Parameter(title: "Suchbegriff")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared?.pendingSearch = query
        return .result()
    }
}

struct AskArchiveIntent: AppIntent {
    static var title: LocalizedStringResource = "Archiv fragen"
    static var description = IntentDescription("Stellt eine Frage an dein Dokumentenarchiv.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStore.shared?.requestAskArchive = true
        return .result()
    }
}

// MARK: - Shortcuts

struct PaperlessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanDocumentIntent(),
            phrases: [
                "Scanne ein Dokument mit \(.applicationName)",
                "Neues Dokument in \(.applicationName)"
            ],
            shortTitle: "Scannen",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: OpenInboxIntent(),
            phrases: [
                "Öffne den Posteingang in \(.applicationName)",
                "Zeige \(.applicationName) Posteingang"
            ],
            shortTitle: "Posteingang",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: SearchDocumentsIntent(),
            phrases: [
                "Suche in \(.applicationName)",
                "Durchsuche \(.applicationName)"
            ],
            shortTitle: "Suchen",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: AskArchiveIntent(),
            phrases: [
                "Frage mein Archiv in \(.applicationName)",
                "Frage \(.applicationName)"
            ],
            shortTitle: "Archiv fragen",
            systemImageName: "sparkles"
        )
    }
}
