import Foundation

enum AppConstants {
    static let appGroupId = "group.com.Thomas.paperless"
    static let appVersion = "1.1.0"
    static let urlScheme = "paperlesstedi"

    static let appChangelog: [ChangelogEntry] = [
        ChangelogEntry(version: "1.1.0", date: "15.02.2026", changes: [
            "Fix für Apple Review (iPad Layout)",
            "Fix: FaceID Loop",
            "Fix: Scanner & Import"
        ]),
        ChangelogEntry(version: "1.0.0", date: "06.02.2026", changes: ["Initialer Release"]),
    ]
}
