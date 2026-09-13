import SwiftUI

/// „Was fehlt" — regelmäßige Dokumente und ihre Lücken.
struct SeriesView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    /// Einmal berechnet, wenn sich der Bestand ändert. Vorher war das eine berechnete
    /// Eigenschaft: Die Erkennung lief über alle Dokumente — zweimal pro Body-Auswertung und
    /// bei jeder Änderung am Store erneut.
    @State private var series: [SeriesDetector.Series] = []

    private var inputKey: Int {
        var hasher = Hasher()
        hasher.combine(store.documents.count)
        hasher.combine(store.documents.first?.id)
        hasher.combine(store.allCorrespondents.count)
        hasher.combine(store.allDocTypes.count)
        return hasher.finalize()
    }

    var body: some View {
        List {
            let problems = series.filter(\.hasProblem)
            let healthy = series.filter { !$0.hasProblem }

            if !problems.isEmpty {
                Section {
                    ForEach(problems) { item in row(item) }
                } header: {
                    Text("Auffällig")
                } footer: {
                    Text("Entweder fehlt ein Monat mitten in der Reihe, oder seit zwei Monaten "
                         + "kam nichts mehr.")
                }
            }

            if !healthy.isEmpty {
                Section("Vollständig") {
                    ForEach(healthy) { item in row(item) }
                }
            }

            if series.isEmpty {
                Section {
                    Text("Keine regelmäßigen Reihen erkannt. Nötig sind mindestens "
                         + "\(SeriesDetector.minimumOccurrences) Belege desselben Senders in "
                         + "aufeinanderfolgenden Monaten.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .themedSurface(palette)
        .navigationTitle("Regelmäßiges")
        .task(id: inputKey) {
            let docs = store.documents
            let names = Dictionary(store.allCorrespondents.map { ($0.id, $0.safeName) },
                                   uniquingKeysWith: { a, _ in a })
            let typeNames = Dictionary(store.allDocTypes.map { ($0.id, $0.safeName) },
                                       uniquingKeysWith: { a, _ in a })
            let result = await Task.detached(priority: .userInitiated) {
                SeriesDetector.detect(in: docs, names: names, typeNames: typeNames)
            }.value
            guard !Task.isCancelled else { return }
            series = result
        }
    }

    private func row(_ item: SeriesDetector.Series) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.subheadline)
            HStack(spacing: 8) {
                Label("\(item.months.count)", systemImage: "calendar")
                    .font(.caption2).foregroundColor(.secondary)
                if item.monthsSinceLast >= 2 {
                    Label("seit \(item.monthsSinceLast) Monaten nichts",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
            if !item.missingMonths.isEmpty {
                Text("Fehlt: \(item.missingMonths.map(readable).joined(separator: ", "))")
                    .font(.caption).foregroundColor(.red)
            }
        }
    }

    /// „2026-04" → „04/2026".
    private func readable(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 2 ? "\(parts[1])/\(parts[0])" : key
    }
}
