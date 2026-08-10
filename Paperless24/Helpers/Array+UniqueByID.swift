import Foundation

extension Array where Element: Identifiable {

    /// Entfernt Elemente mit bereits vorhandener ID und behält das erste Vorkommen.
    ///
    /// SwiftUI identifiziert Zeilen in `ForEach` über die ID. Tauchen zwei Elemente mit
    /// derselben ID auf, verliert SwiftUI die Zuordnung von Zelle zu Element: Tippen läuft
    /// ins Leere und Kontextmenüs öffnen an der falschen Stelle. Die Server-Antworten von
    /// paperless-ngx können bei gleichrangiger Sortierung dasselbe Dokument auf mehreren
    /// Seiten liefern — deshalb wird jede Seite vor dem Anhängen bereinigt.
    func uniquedByID() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }

    /// Hängt nur Elemente an, deren ID noch nicht enthalten ist.
    mutating func appendUniqueByID(_ newElements: [Element]) {
        var seen = Set(map(\.id))
        for element in newElements where seen.insert(element.id).inserted {
            append(element)
        }
    }
}

extension Array {

    /// Zerlegt das Array in Blöcke von höchstens `size` Elementen. Der letzte Block ist kürzer.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
