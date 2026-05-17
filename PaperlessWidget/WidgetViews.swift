import SwiftUI
import WidgetKit

// MARK: - Hilfs-View: eine Dokumentenzeile

struct DocRow: View {
    let doc: WidgetDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(doc.title)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1)
            Text(formattedDate(doc.created))
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private func formattedDate(_ s: String) -> String {
        guard let d = Self.isoFormatter.date(from: String(s.prefix(10))) else { return s }
        return Self.displayFormatter.string(from: d)
    }
}

// MARK: - Deaktiviert-View (gemeinsam für alle Größen)

struct WidgetDisabledView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 28)).foregroundColor(.accentColor)
            Text("Paperless24")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small

struct SmallDocumentsView: View {
    let doc: WidgetDocument?

    var body: some View {
        if let doc = doc {
            Link(destination: URL(string: "paperless24://document?id=\(doc.id)")!) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text(doc.title)
                        .font(.caption).fontWeight(.semibold).lineLimit(2)
                    if let corr = doc.correspondent {
                        Text(corr).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetDisabledView()
        }
    }
}

struct SmallOverviewView: View {
    let inbox: Int
    var body: some View {
        VStack(spacing: 4) {
            Text("\(inbox)")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.accentColor)
            Text("Posteingang")
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "paperless24://open"))
    }
}

private func relativeSyncText(_ date: Date?) -> String {
    guard let d = date else { return "–" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: d, relativeTo: Date())
}

// MARK: - Medium

struct MediumDocumentsView: View {
    let docs: [WidgetDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.accentColor).font(.caption)
                Text("Zuletzt hinzugefügt").font(.caption2).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)

            let sliced = Array(docs.prefix(2))
            ForEach(Array(sliced.enumerated()), id: \.element.id) { index, doc in
                Link(destination: URL(string: "paperless24://document?id=\(doc.id)")!) {
                    DocRow(doc: doc)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                }
                if index < sliced.count - 1 {
                    Divider().padding(.horizontal, 12)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumOverviewView: View {
    let inbox: Int
    let total: Int
    let lastSync: Date?

    var body: some View {
        HStack(spacing: 0) {
            statItem(value: "\(inbox)", label: "Posteingang", icon: "tray.fill", color: .pink)
            Divider().padding(.vertical, 12)
            statItem(value: "\(total)", label: "Dokumente", icon: "doc.text.fill", color: .blue)
            Divider().padding(.vertical, 12)
            statItem(value: relativeSyncText(lastSync), label: "Sync", icon: "arrow.clockwise", color: .green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "paperless24://open"))
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 18))
            Text(value).font(.headline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large

struct LargeDocumentsView: View {
    let docs: [WidgetDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.accentColor).font(.caption)
                Text("Zuletzt hinzugefügt").font(.caption2).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            ForEach(docs.prefix(5)) { doc in
                Link(destination: URL(string: "paperless24://document?id=\(doc.id)")!) {
                    DocRow(doc: doc).padding(.horizontal, 14).padding(.vertical, 5)
                }
                Divider().padding(.horizontal, 14)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LargeOverviewView: View {
    let inbox: Int
    let total: Int
    let lastSync: Date?
    let docs: [WidgetDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                overviewStat(value: "\(inbox)", label: "Posteingang", icon: "tray.fill", color: .pink)
                overviewStat(value: "\(total)", label: "Dokumente", icon: "doc.text.fill", color: .blue)
                overviewStat(value: relativeSyncText(lastSync), label: "Sync", icon: "arrow.clockwise", color: .green)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider().padding(.horizontal, 14)

            Text("Zuletzt hinzugefügt")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)

            ForEach(docs.prefix(2)) { doc in
                Link(destination: URL(string: "paperless24://document?id=\(doc.id)")!) {
                    DocRow(doc: doc).padding(.horizontal, 14).padding(.vertical, 4)
                }
                Divider().padding(.horizontal, 14)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "paperless24://open"))
    }

    private func overviewStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 14))
            Text(value).font(.subheadline).fontWeight(.bold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

}
