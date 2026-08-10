import SwiftUI

/// Sucht Netzwerkscanner und scannt direkt in den Upload-Flow.
struct AirScanView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = AirScanService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if service.scanners.isEmpty {
                        HStack {
                            ProgressView()
                            Text(service.isDiscovering ? "Suche Scanner …" : "Keine Scanner gefunden")
                                .foregroundColor(.secondary)
                        }
                    }
                    ForEach(service.scanners) { scanner in
                        Button {
                            Task { await scan(scanner) }
                        } label: {
                            HStack {
                                Image(systemName: "scanner").foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(scanner.name).foregroundColor(.primary)
                                    Text("\(scanner.host):\(scanner.port)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if service.isScanning { ProgressView() }
                            }
                        }
                        .disabled(service.isScanning)
                    }
                } footer: {
                    Text("Findet AirScan-/eSCL-fähige Scanner im lokalen Netzwerk. Funktioniert nicht mit jedem Modell.")
                }

                if !service.statusText.isEmpty {
                    Section { Text(service.statusText).font(.caption).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Netzwerkscanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { service.startDiscovery() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear { service.startDiscovery() }
            .onDisappear { service.stopDiscovery() }
        }
    }

    private func scan(_ scanner: AirScanService.DiscoveredScanner) async {
        if let data = await service.scan(scanner) {
            store.handleImportData(data: data, filename: "AirScan_\(Date().timeIntervalSince1970).pdf")
            dismiss()
        }
    }
}
