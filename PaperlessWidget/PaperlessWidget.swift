import WidgetKit
import SwiftUI

struct PaperlessEntry: TimelineEntry {
    let date: Date
    let docs: [WidgetDocument]
    let inboxCount: Int
    let totalCount: Int
    let lastSync: Date?
    let mode: String
    let enabled: Bool
}

struct PaperlessTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaperlessEntry {
        PaperlessEntry(
            date: Date(),
            docs: [
                WidgetDocument(id: 1, title: "Rechnung Amazon", created: "2026-05-01", correspondent: "Amazon"),
                WidgetDocument(id: 2, title: "Kontoauszug Mai", created: "2026-05-10", correspondent: "Bank")
            ],
            inboxCount: 3,
            totalCount: 142,
            lastSync: Date(),
            mode: "documents",
            enabled: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PaperlessEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaperlessEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> PaperlessEntry {
        let stats = WidgetDataService.readStats()
        return PaperlessEntry(
            date: Date(),
            docs: WidgetDataService.readDocuments(),
            inboxCount: stats.inbox,
            totalCount: stats.total,
            lastSync: stats.lastSync,
            mode: WidgetDataService.readMode(),
            enabled: WidgetDataService.isEnabled()
        )
    }
}

struct PaperlessWidgetEntryView: View {
    let entry: PaperlessEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.enabled {
            WidgetDisabledView()
        } else if entry.mode == "overview" {
            overviewView
        } else {
            documentsView
        }
    }

    @ViewBuilder
    private var documentsView: some View {
        switch family {
        case .systemSmall:
            SmallDocumentsView(doc: entry.docs.first)
        case .systemMedium:
            MediumDocumentsView(docs: entry.docs)
        case .systemLarge:
            LargeDocumentsView(docs: entry.docs)
        default:
            SmallDocumentsView(doc: entry.docs.first)
        }
    }

    @ViewBuilder
    private var overviewView: some View {
        switch family {
        case .systemSmall:
            SmallOverviewView(inbox: entry.inboxCount)
        case .systemMedium:
            MediumOverviewView(inbox: entry.inboxCount, total: entry.totalCount, lastSync: entry.lastSync)
        case .systemLarge:
            LargeOverviewView(inbox: entry.inboxCount, total: entry.totalCount, lastSync: entry.lastSync, docs: entry.docs)
        default:
            SmallOverviewView(inbox: entry.inboxCount)
        }
    }
}

struct PaperlessWidget: Widget {
    let kind = "PaperlessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaperlessTimelineProvider()) { entry in
            PaperlessWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Paperless TeDi")
        .description("Zeigt deine zuletzt hinzugefügten Dokumente oder eine Übersicht.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
