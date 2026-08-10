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
            // Die tatsächliche Fundstelle übernehmen, nicht per `attr.range(of:)` suchen:
            // die Suche liefert immer das erste Vorkommen — steht dieselbe Nummer zweimal
            // im Text, bekäme die erste beide Links und die zweite bliebe tot.
            guard let textRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(textRange.lowerBound, within: attr),
                  let upper = AttributedString.Index(textRange.upperBound, within: attr) else { return }
            let range = lower..<upper

            switch match.resultType {
            case .link:
                if let url = match.url { attr[range].link = url }
            case .phoneNumber:
                if let number = match.phoneNumber {
                    let digits = number.filter { !$0.isWhitespace }
                    if let url = URL(string: "tel:\(digits)") { attr[range].link = url }
                }
            case .address:
                // Über `URLComponents`, damit ein `&` in der Adresse nicht als Parametertrenner
                // gelesen wird. Und über HTTPS statt HTTP.
                var comps = URLComponents(string: "https://maps.apple.com/")
                comps?.queryItems = [URLQueryItem(name: "q", value: sub)]
                if let url = comps?.url { attr[range].link = url }
            default:
                break
            }
        }
        return attr
    }
}
