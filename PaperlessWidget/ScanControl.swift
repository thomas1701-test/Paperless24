import WidgetKit
import SwiftUI
import AppIntents

/// Scannen aus dem Control Center, vom Sperrbildschirm und über die Aktionstaste.
///
/// Der Weg vom Papier zur App war bisher: entsperren, App suchen, öffnen, Plus antippen,
/// Kamera wählen. Ein Control hier macht daraus einen Tipp.
@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    let kind = "PaperlessScanControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: OpenScannerIntent()) {
                Label("Scannen", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Dokument scannen")
        .description("Öffnet Paperless 24 direkt im Scanner.")
    }
}

/// Öffnet die App im Scanner.
///
/// `openAppWhenRun` ist nötig, weil der Dokumentenscanner eine Kameraoberfläche braucht — im
/// Control selbst lässt sich das nicht zeigen.
@available(iOS 18.0, *)
struct OpenScannerIntent: AppIntent {
    static var title: LocalizedStringResource = "Dokument scannen"
    static var description = IntentDescription("Öffnet Paperless 24 und startet den Scanner.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // Das URL-Schema ist der Weg, den auch Widget und Spotlight nehmen; die App wertet
        // ihn beim Start aus.
        UserDefaults(suiteName: "group.com.Thomas.paperless")?.set(true, forKey: "control_request_scan")
        return .result()
    }
}

/// Posteingang öffnen — als zweites Control für die Leiste.
@available(iOS 18.0, *)
struct InboxControl: ControlWidget {
    let kind = "PaperlessInboxControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: OpenInboxControlIntent()) {
                Label("Posteingang", systemImage: "tray")
            }
        }
        .displayName("Posteingang")
        .description("Öffnet den Posteingang in Paperless 24.")
    }
}

@available(iOS 18.0, *)
struct OpenInboxControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Posteingang öffnen"
    static var description = IntentDescription("Öffnet Paperless 24 im Posteingang.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.com.Thomas.paperless")?.set(true, forKey: "control_request_inbox")
        return .result()
    }
}
