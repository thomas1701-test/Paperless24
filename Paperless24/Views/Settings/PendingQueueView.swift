import SwiftUI

struct PendingQueueView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section(header: Text("Uploads")) {
                if store.pendingUploads.isEmpty { Text("Leer").foregroundColor(.secondary) }
                ForEach(store.pendingUploads) { item in
                    HStack {
                        Image(systemName: "doc")
                        Text(item.title)
                        Spacer()
                        Image(systemName: "clock").foregroundColor(.orange)
                    }
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
                    HStack {
                        Image(systemName: "pencil")
                        Text(item.title)
                        Spacer()
                        Image(systemName: "clock").foregroundColor(.blue)
                    }
                }
                .onDelete(perform: store.removePendingEdit)
            }
        }
        .themedSurface(palette)
        .navigationTitle("Warteschlange")
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
