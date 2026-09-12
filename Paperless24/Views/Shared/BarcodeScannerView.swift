import SwiftUI
import VisionKit

/// Barcode-Scanner für ASN-Aufkleber.
///
/// Wer sein Papier zusätzlich physisch archiviert, klebt auf jeden Ordnerbeleg die
/// Archiv-Seriennummer. Die Brücke vom Blatt zurück in die App fehlte bisher: Man musste die
/// Nummer ablesen und von Hand suchen.
struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// Wird mit dem erkannten Text aufgerufen.
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            // ASN-Etiketten aus paperless-ngx sind üblicherweise Code128 oder QR; die
            // Einschränkung auf Barcodes verhindert, dass der Scanner Text im Dokument liest.
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if isPresented {
            try? controller.startScanning()
        } else {
            controller.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let parent: BarcodeScannerView
        /// Gegen Mehrfachtreffer: Der Scanner meldet denselben Code mehrmals pro Sekunde.
        private var handled = false

        init(parent: BarcodeScannerView) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(items)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !handled else { return }
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    handled = true
                    parent.onScan(payload)
                    parent.isPresented = false
                    return
                }
            }
        }
    }
}

/// Blatt um den Scanner: sucht das Dokument zur erkannten Nummer.
struct ASNScannerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// Wird mit dem gefundenen Dokument aufgerufen.
    let onFound: (Document) -> Void

    @State private var isScanning = true
    @State private var status: String? = nil
    @State private var isSearching = false
    @State private var manualEntry = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if BarcodeScannerView.isSupported {
                    BarcodeScannerView(isPresented: $isScanning) { payload in
                        Task { await lookUp(payload) }
                    }
                } else {
                    // Simulator und ältere Geräte ohne Neural Engine für DataScanner.
                    VStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder").font(.largeTitle)
                        Text("Barcode-Scanner auf diesem Gerät nicht verfügbar.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                VStack(spacing: 8) {
                    HStack {
                        TextField("ASN von Hand eingeben", text: $manualEntry)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Button("Suchen") { Task { await lookUp(manualEntry) } }
                            .disabled(manualEntry.isEmpty || isSearching)
                    }
                    if isSearching { ProgressView() }
                    if let status {
                        Text(status).font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("ASN scannen")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface(palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
    }

    /// Sucht das Dokument zur Nummer im Barcode.
    ///
    /// Aus dem Code wird die erste Zahlenfolge genommen: Viele Etiketten drucken ein Präfix
    /// („ASN00042"), manche eine URL mit der Nummer am Ende.
    private func lookUp(_ payload: String) async {
        let digits = payload.filter(\.isNumber)
        guard let asn = Int(digits), asn > 0 else {
            status = "Im Code steckt keine Nummer: \(payload)"
            isScanning = true
            return
        }
        isSearching = true
        status = "Suche ASN \(asn)…"
        if let doc = await store.findDocument(asn: asn) {
            isSearching = false
            dismiss()
            onFound(doc)
        } else {
            isSearching = false
            status = "Kein Dokument mit ASN \(asn) gefunden."
            isScanning = true
        }
    }
}
