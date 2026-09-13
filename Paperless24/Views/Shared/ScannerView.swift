import SwiftUI
import VisionKit

struct ScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onScan: (Data) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ScannerView
        init(parent: ScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Verkleinert und als JPEG — siehe `ScanPDF`.
            let data = ScanPDF.make(pageCount: scan.pageCount) { scan.imageOfPage(at: $0) }
            parent.onScan(data)
            parent.isPresented = false
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }
    }
}
