import Foundation

/// Alle Filter der Dokumentliste an einem Ort, übersetzt in Query-Parameter für
/// `/api/documents/`.
///
/// Bis Version 2.1.4 filterte die App ausschließlich lokal (`AppStore.updateFilteredDocs`)
/// über die Dokumente, die gerade geladen waren. Bei der Standard-Seitengröße von 25 hat
/// „Tag = Versicherung" damit 25 von mehreren tausend Dokumenten durchsucht und das Ergebnis
/// als vollständig ausgegeben. Sortiert hat dagegen immer der Server. Seit 2.2 geht beides
/// an den Server, und die Liste blättert *innerhalb* des Filters weiter.
///
/// Mengen statt Einzelwerte: `tags__id__all` & Co. nehmen Listen, die Mehrfachauswahl in der
/// Oberfläche kostet damit keine Änderung mehr an dieser Stelle.
struct DocumentQuery: Equatable {
    /// Dokument muss **alle** diese Tags tragen (`tags__id__all`).
    var tagIDs: Set<Int> = []
    /// Dokument darf **keinen** dieser Tags tragen (`tags__id__none`).
    var excludedTagIDs: Set<Int> = []
    /// Einer dieser Sender (`correspondent__id__in`).
    var correspondentIDs: Set<Int> = []
    /// Einer dieser Typen (`document_type__id__in`).
    var documentTypeIDs: Set<Int> = []
    /// Einer dieser Speicherpfade (`storage_path__id__in`).
    var storagePathIDs: Set<Int> = []
    /// Belegdatum ab / bis (`created__date__gte` / `created__date__lte`).
    var createdFrom: Date? = nil
    var createdTo: Date? = nil
    /// Dokument hat dieses eigene Feld ausgefüllt (`custom_fields__id__all`).
    var customFieldID: Int? = nil
    /// Textvergleich im Wert des eigenen Feldes.
    ///
    /// Bleibt bewusst lokal: Für die Wertsuche gibt es je ngx-Version unterschiedliche
    /// Parameter (`custom_field_query` erst ab 2.x mit eigener JSON-Syntax). Ein falscher
    /// Parameter beantwortet der Server mit 400 und die Liste wäre leer — hier zählt
    /// Verlässlichkeit mehr als die letzte Einschränkung. Der Server liefert also alle
    /// Dokumente *mit* dem Feld, der Text grenzt die geladenen davon weiter ein.
    var customFieldText: String = ""
    /// Volltextsuche (`query`).
    var searchText: String = ""

    /// Kein Filter und keine Suche — die unveränderte Gesamtliste.
    var isEmpty: Bool { !hasFilters && searchText.isEmpty }

    /// Mindestens ein Filter (ohne Suchbegriff) ist gesetzt.
    var hasFilters: Bool {
        !tagIDs.isEmpty || !excludedTagIDs.isEmpty || !correspondentIDs.isEmpty
            || !documentTypeIDs.isEmpty || !storagePathIDs.isEmpty
            || createdFrom != nil || createdTo != nil || customFieldID != nil
    }

    /// Wird der Textvergleich für ein eigenes Feld noch lokal nachgezogen?
    var needsLocalCustomFieldMatch: Bool {
        customFieldID != nil && !customFieldText.isEmpty
    }

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        func add(_ name: String, _ ids: Set<Int>) {
            guard !ids.isEmpty else { return }
            items.append(URLQueryItem(name: name, value: ids.sorted().map(String.init).joined(separator: ",")))
        }

        add("tags__id__all", tagIDs)
        add("tags__id__none", excludedTagIDs)
        add("correspondent__id__in", correspondentIDs)
        add("document_type__id__in", documentTypeIDs)
        add("storage_path__id__in", storagePathIDs)

        if let from = createdFrom {
            items.append(URLQueryItem(name: "created__date__gte", value: DateFormatting.apiDate(from)))
        }
        if let to = createdTo {
            items.append(URLQueryItem(name: "created__date__lte", value: DateFormatting.apiDate(to)))
        }
        if let field = customFieldID {
            items.append(URLQueryItem(name: "custom_fields__id__all", value: "\(field)"))
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            items.append(URLQueryItem(name: "query", value: trimmedSearch))
        }
        return items
    }
}

extension DocumentQuery {
    /// Baut die Datumsgrenzen aus der Voreinstellung der Oberfläche.
    ///
    /// „Letzter Monat" und „Dieses Jahr" haben nur eine Untergrenze; das obere Ende ist offen,
    /// damit Dokumente mit einem Belegdatum in der Zukunft (Rechnung mit Fälligkeit, Vertrag
    /// ab nächstem Monat) nicht aus der Liste fallen.
    static func dateBounds(
        filter: DateFilter, customStart: Date, customEnd: Date, now: Date = Date(),
        calendar: Calendar = .current
    ) -> (from: Date?, to: Date?) {
        switch filter {
        case .all:
            return (nil, nil)
        case .lastMonth:
            return (calendar.date(byAdding: .month, value: -1, to: now), nil)
        case .thisYear:
            return (calendar.date(from: calendar.dateComponents([.year], from: now)), nil)
        case .custom:
            return (calendar.startOfDay(for: customStart), calendar.startOfDay(for: customEnd))
        }
    }
}

/// Merkt sich je Server, ob er die Filterparameter aus `DocumentQuery` versteht.
///
/// Ein unbekannter Query-Parameter beantwortet paperless-ngx mit 400. Ohne diesen Schalter
/// würde die App bei jedem Filterklick erneut in den Fehler laufen und eine leere Liste
/// zeigen. Einmal abgeschaltet, filtert die App für diesen Server wieder lokal — also genau
/// so, wie sie es bis 2.1.4 immer getan hat.
enum DocumentFilterSupport {
    private static func key(_ server: String) -> String { "paperlessServerFilters.\(server)" }

    static func isSupported(_ server: String) -> Bool {
        guard !server.isEmpty else { return false }
        return UserDefaults.standard.object(forKey: key(server)) as? Bool ?? true
    }

    static func disable(_ server: String) {
        guard !server.isEmpty else { return }
        UserDefaults.standard.set(false, forKey: key(server))
    }

    /// Für die Diagnose-Ansicht und den Kontowechsel: erneut versuchen.
    static func reset(_ server: String) {
        UserDefaults.standard.removeObject(forKey: key(server))
    }
}
