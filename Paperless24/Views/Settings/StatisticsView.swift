import SwiftUI

/// Kennzahlen zum Archiv.
///
/// Rechnet ausschließlich auf den geladenen Dokumenten und sagt das auch — eine Auswertung,
/// die vorgibt, das ganze Archiv zu kennen, während sie nur die erste Seite sieht, wäre
/// schlimmer als gar keine.
struct StatisticsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @State private var serverTotal: Int? = nil

    private var docs: [Document] { store.documents }

    var body: some View {
        List {
            Section("Bestand") {
                statRow("Dokumente auf dem Server", serverTotal.map(String.init) ?? "—")
                statRow("Davon geladen", "\(docs.count)")
                statRow("Posteingang", "\(store.inboxCount)")
                statRow("Tags", "\(store.allTags.count)")
                statRow("Sender", "\(store.allCorrespondents.count)")
                statRow("Typen", "\(store.allDocTypes.count)")
            }

            if !monthlyCounts.isEmpty {
                Section {
                    ForEach(monthlyCounts, id: \.label) { item in
                        HStack(spacing: 10) {
                            Text(item.label)
                                .font(.caption.monospacedDigit())
                                .frame(width: 62, alignment: .leading)
                            // Balken statt Diagramm-Bibliothek: eine Zeile, die sich an die
                            // Breite anpasst und in jeder Schriftgröße lesbar bleibt.
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette.accent.opacity(0.75))
                                    .frame(width: max(2, geo.size.width * item.share))
                            }
                            .frame(height: 12)
                            Text("\(item.count)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("Dokumente pro Monat")
                } footer: {
                    Text("Nach Belegdatum, letzte 12 Monate mit Einträgen.")
                }
            }

            if !topCorrespondents.isEmpty {
                Section("Häufigste Sender") {
                    ForEach(topCorrespondents, id: \.name) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text("\(item.count)").foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Speicher") {
                statRow("Zwischengespeicherte Dateien", "\(store.cachedCount)")
                statRow("Belegter Platz", store.storageSize)
            }

            if docs.count < (serverTotal ?? 0) {
                Section {
                    Text("Die Auswertung nutzt die \(docs.count) geladenen Dokumente. Für das "
                         + "ganze Archiv in den Einstellungen eine größere Seitengröße wählen "
                         + "oder alle Dokumente herunterladen.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .themedSurface(palette)
        .navigationTitle("Statistik")
        .task {
            serverTotal = await store.fetchStatistics()?.documentsTotal
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    // MARK: - Auswertung

    private struct MonthCount { let label: String; let count: Int; let share: Double }

    private var monthlyCounts: [MonthCount] {
        var buckets: [String: Int] = [:]
        for doc in docs {
            guard doc.created.count >= 7 else { continue }
            buckets[String(doc.created.prefix(7)), default: 0] += 1
        }
        let sorted = buckets.sorted { $0.key > $1.key }.prefix(12)
        let maximum = sorted.map(\.value).max() ?? 1
        return sorted.map { key, value in
            let parts = key.split(separator: "-")
            let label = parts.count == 2 ? "\(parts[1]).\(parts[0])" : key
            return MonthCount(label: label, count: value,
                              share: Double(value) / Double(maximum))
        }
    }

    private var topCorrespondents: [(name: String, count: Int)] {
        var buckets: [Int: Int] = [:]
        for doc in docs {
            guard let id = doc.correspondent else { continue }
            buckets[id, default: 0] += 1
        }
        let names = Dictionary(store.allCorrespondents.map { ($0.id, $0.safeName) },
                               uniquingKeysWith: { a, _ in a })
        return buckets
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { (name: names[$0.key] ?? "Unbekannt", count: $0.value) }
    }
}
