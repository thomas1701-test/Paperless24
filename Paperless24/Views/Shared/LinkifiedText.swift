import SwiftUI

/// Rendert Text und macht erkannte Telefonnummern, Links und Adressen tappbar
/// (Live-Text-ähnliche Aktionen). Text bleibt auswählbar.
struct LinkifiedText: View {
    let text: String

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .tint(.blue)
    }

    private var attributed: AttributedString {
        var attr = AttributedString(text)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return attr }

        let ns = text as NSString
        detector.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let sub = ns.substring(with: match.range)
            guard let range = attr.range(of: sub) else { return }

            switch match.resultType {
            case .link:
                if let url = match.url { attr[range].link = url }
            case .phoneNumber:
                if let number = match.phoneNumber {
                    let digits = number.filter { !$0.isWhitespace }
                    if let url = URL(string: "tel:\(digits)") { attr[range].link = url }
                }
            case .address:
                let q = sub.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sub
                if let url = URL(string: "http://maps.apple.com/?q=\(q)") { attr[range].link = url }
            default:
                break
            }
        }
        return attr
    }
}
