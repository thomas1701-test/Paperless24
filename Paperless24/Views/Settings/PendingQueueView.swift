import SwiftUI

struct PendingQueueView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section(header: Text("Uploads")) {
                if store.pendingUploads.isEmpty { Text("Leer").foregroundColor(.secondary) }
                ForEach(store.pendingUploads) { item in
                    queueRow(title: item.title, symbol: "doc", failureReason: item.failureReason,
                             waitingColor: .orange)
                }
                .onDelete(perform: store.removePendingUpload)
            }
            if !store.uploadTaskStatuses.isEmpty {
                Section {
                    ForEach(store.uploadTaskStatuses) { task in
                        HStack(alignment: .top) {
                            Image(systemName: task.symbolName)
                                .foregroundColor(color(for: task.state))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                if let message = task.message {
                                    Text(message).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if task.state == .waiting || task.state == .running {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    if store.uploadTaskStatuses.contains(where: \.isFinished) {
                        Button("Erledigte ausblenden") { store.clearFinishedTaskStatuses() }
                    }
                } header: {
                    Text("Verarbeitung auf dem Server")
                } footer: {
                    Text("Der Server nimmt eine Datei sofort an, verarbeitet sie aber danach — "
                         + "OCR, Dublettenprüfung, Zuordnung. Hier steht, was daraus geworden ist.")
                }
            }

            Section(header: Text("Bearbeitungen")) {
                if store.pendingEdits.isEmpty { Text("Leer").foregroundColor(.secondary) }
                ForEach(store.pendingEdits) { item in
                    queueRow(title: item.title, symbol: "pencil", failureReason: item.failureReason,
                             waitingColor: .blue)
                }
                .onDelete(perform: store.removePendingEdit)
            }

            if hasRejected {
                Section {
                    Button("Abgelehnte erneut versuchen") { store.retryRejectedQueueItems() }
                } footer: {
                    Text("Der Server hat diese Einträge abgelehnt. Die übrigen werden trotzdem übertragen. Zum Verwerfen nach links wischen.")
                }
            }
        }
        .themedSurface(palette)
        .navigationTitle("Warteschlange")
    }

    private var hasRejected: Bool {
        store.pendingUploads.contains { $0.failureReason != nil }
            || store.pendingEdits.contains { $0.failureReason != nil }
    }

    private func queueRow(title: String, symbol: String, failureReason: String?,
                          waitingColor: Color) -> some View {
        HStack(alignment: .top) {
            Image(systemName: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let failureReason {
                    Text(failureReason).font(.caption).foregroundColor(.red)
                }
            }
            Spacer()
            if failureReason != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            } else {
                Image(systemName: "clock").foregroundColor(waitingColor)
            }
        }
    }

    private func color(for state: UploadTaskStatus.State) -> Color {
        switch state {
        case .waiting, .running: return .orange
        case .succeeded:         return .green
        case .failed:            return .red
        case .duplicate:         return .yellow
        case .unknown:           return .secondary
        }
    }
}
