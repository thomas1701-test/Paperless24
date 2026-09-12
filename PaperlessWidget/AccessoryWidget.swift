import WidgetKit
import SwiftUI

/// Posteingangszahl für den Sperrbildschirm (und die Apple Watch, wo verfügbar).
///
/// Der Rückstand im Posteingang ist die einzige Zahl, die man mehrmals täglich sehen will —
/// und genau dafür sind die Zubehör-Familien gemacht. Bisher unterstützte das Widget nur die
/// drei Homescreen-Größen.
struct InboxAccessoryWidget: Widget {
    let kind = "PaperlessInboxAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaperlessTimelineProvider()) { entry in
            InboxAccessoryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Posteingang")
        .description("Zeigt, wie viele Dokumente unbearbeitet sind.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct InboxAccessoryView: View {
    let entry: PaperlessEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // Kein Hintergrund, keine Farbe: Der Sperrbildschirm zeichnet Zubehör-Widgets
            // einfarbig, alles andere wird ohnehin überschrieben.
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "tray").font(.system(size: 11))
                    Text("\(entry.inboxCount)").font(.system(size: 16, weight: .semibold))
                }
            }
            .widgetURL(URL(string: "paperless24://inbox"))

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Posteingang", systemImage: "tray")
                    .font(.caption2)
                    .widgetAccentable()
                Text(entry.inboxCount == 0 ? "Alles bearbeitet" : "\(entry.inboxCount) unbearbeitet")
                    .font(.headline)
                if let sync = entry.lastSync {
                    Text(sync, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetURL(URL(string: "paperless24://inbox"))

        default:
            // `accessoryInline` erlaubt genau eine Textzeile mit optionalem Symbol.
            Label("\(entry.inboxCount) im Posteingang", systemImage: "tray")
                .widgetURL(URL(string: "paperless24://inbox"))
        }
    }
}
