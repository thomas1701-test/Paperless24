import WidgetKit
import SwiftUI

@main
struct PaperlessWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaperlessWidget()
        InboxAccessoryWidget()
        // Controls gibt es erst ab iOS 18. Die Verfügbarkeitsprüfung gehört in den Bundle-
        // Rumpf, weil `WidgetBundle` keine Bedingungen auf Typebene erlaubt.
        if #available(iOS 18.0, *) {
            ScanControl()
            InboxControl()
        }
    }
}
