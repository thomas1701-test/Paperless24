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
            let renderer = UIGraphicsPDFRenderer()
            let data = renderer.pdfData { ctx in
                for i in 0..<scan.pageCount {
                    let img = scan.imageOfPage(at: i)
                    let rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
                    ctx.beginPage(withBounds: rect, pageInfo: [:])
                    img.draw(in: rect)
                }
            }
            parent.onScan(data)
            parent.isPresented = false
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }
    }
}
