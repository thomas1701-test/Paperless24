import SwiftUI
import VisionKit

/// Dokumentenscanner, der die einzelnen Seiten als Bilder zurückgibt
/// (für Stapel-Trennung und Dublettencheck).
struct PageScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: PageScannerView
        init(parent: PageScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            for i in 0..<scan.pageCount { pages.append(scan.imageOfPage(at: i)) }
            parent.onScan(pages)
            parent.isPresented = false
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }
    }
}
