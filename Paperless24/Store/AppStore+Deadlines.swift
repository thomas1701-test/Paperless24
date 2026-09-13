import Foundation

/// Ein bestätigter Fristeneintrag: Dokument plus Datum aus dem eigenen Feld.
struct DeadlineEntry: Identifiable, Hashable {
    let document: Document
    let date: Date

    var id: Int { document.id }

    var daysRemaining: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: date)).day ?? 0
    }
    var isOverdue: Bool { daysRemaining < 0 }
}

/// Fristen-Radar.
///
/// Zweiter Anlauf, bewusst anders gebaut als der verworfene erste: Es wird nichts still im
/// Hintergrund gespeichert. Die Erkennung (`DeadlineDetector`) schlägt vor, der Nutzer
/// bestätigt, und erst die Bestätigung landet als Datum in einem eigenen Feld auf dem Server.
/// Damit steht die Frist auch in der Weboberfläche und auf anderen Geräten — und eine
/// Falscherkennung kostet einen Tipp, nicht das Vertrauen in die Liste.
extension AppStore {

    /// Name des Feldes, das die Frist hält — anlegbar über die Feldverwaltung.
    static let deadlineFieldName = "Fälligkeit"

    var isDeadlineRadarEnabled: Bool {
        UserDefaults.standard.object(forKey: "deadlineRadarEnabled") as? Bool ?? false
    }

    /// Das eigene Feld, in dem die Frist steht. Erst der eingestellte, dann der Standardname.
    var deadlineField: CustomField? {
        let storedId = UserDefaults.standard.integer(forKey: "deadlineFieldId")
        if storedId > 0, let field = allCustomFields.first(where: { $0.id == storedId }) {
            return field
        }
        return customField(named: Self.deadlineFieldName)
    }

    func setDeadlineField(_ field: CustomField?) {
        UserDefaults.standard.set(field?.id ?? 0, forKey: "deadlineFieldId")
    }

    /// Sorgt dafür, dass es ein Datumsfeld für Fristen gibt — und legt es sonst an.
    @discardableResult
    func ensureDeadlineField() async -> CustomField? {
        if let existing = deadlineField, existing.type == .date { return existing }
        guard let created = await createCustomField(name: Self.deadlineFieldName, type: .date) else {
            return nil
        }
        setDeadlineField(created)
        return created
    }

    // MARK: - Vorschläge

    /// Durchsucht die geladenen Dokumente nach belegbaren Fristen, die noch nicht im Feld stehen.
    ///
    /// Läuft über `content`, also den Text, den der Server ohnehin schon geliefert hat — kein
    /// zusätzlicher Netzverkehr, keine Texterkennung auf dem Gerät.
    func deadlineSuggestions(limit: Int = 50) async -> [Deadline] {
        guard isDeadlineRadarEnabled else { return [] }
        let fieldId = deadlineField?.id
        let documents = documents
        // Regex-Suche über den Text aller geladenen Dokumente — abseits des Main Threads.
        return await Task.detached(priority: .userInitiated) {
            Self.deadlineSuggestions(in: documents, fieldId: fieldId, limit: limit)
        }.value
    }

    nonisolated static func deadlineSuggestions(in documents: [Document], fieldId: Int?,
                                                limit: Int) -> [Deadline] {
        var found: [Deadline] = []
        for doc in documents {
            guard let text = doc.content, !text.isEmpty else { continue }
            // Schon bestätigt? Dann nicht erneut vorschlagen.
            if let fieldId, let entry = doc.customFields.first(where: { $0.field == fieldId }),
               !entry.value.isEmpty {
                continue
            }
            if let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: doc.id) {
                found.append(deadline)
            }
            if found.count >= limit { break }
        }
        return found.sorted { $0.date < $1.date }
    }

    /// Schreibt eine bestätigte Frist in das eigene Feld.
    @discardableResult
    func confirmDeadline(_ deadline: Deadline) async -> Bool {
        guard let doc = documents.first(where: { $0.id == deadline.documentId })
                ?? filteredDocs.first(where: { $0.id == deadline.documentId })
                ?? inboxDocuments.first(where: { $0.id == deadline.documentId })
        else { return false }
        let account = activeAccountId
        guard let field = await ensureDeadlineField() else { return false }
        // Während das Feld angelegt wurde, kann das Konto gewechselt haben — dann ginge die
        // Änderung an ein fremdes Dokument mit derselben ID.
        guard activeAccountId == account else { return false }

        var fields = doc.customFields.filter { $0.field != field.id }
        fields.append(CustomFieldEdit(field: field.id,
                                      value: .text(DateFormatting.apiDate(deadline.date))))
        // Über die Warteschlange, damit die Änderung offline nicht verloren geht.
        addPendingEdit(docId: doc.id, title: doc.title, created: doc.dateObject ?? Date(),
                       corr: doc.correspondent, type: doc.documentType,
                       asn: doc.archiveSerialNumber, tags: doc.tags, customFields: fields)
        haptic(.medium)
        return true
    }

    /// Entfernt die Frist aus dem Feld.
    func clearDeadline(for docId: Int) {
        guard let field = deadlineField,
              let doc = documents.first(where: { $0.id == docId })
                ?? filteredDocs.first(where: { $0.id == docId }) else { return }
        let fields = doc.customFields.filter { $0.field != field.id }
        addPendingEdit(docId: doc.id, title: doc.title, created: doc.dateObject ?? Date(),
                       corr: doc.correspondent, type: doc.documentType,
                       asn: doc.archiveSerialNumber, tags: doc.tags, customFields: fields)
    }

    // MARK: - Bestätigte Fristen laden

    /// Alle Dokumente mit gesetzter Frist, nach Datum sortiert.
    ///
    /// Holt sie über den Server-Filter (`custom_fields__id__all`), damit die Liste das ganze
    /// Archiv abdeckt und nicht nur die geladene Seite.
    func loadDeadlines() async -> [DeadlineEntry] {
        guard let field = deadlineField else { return [] }

        var candidates: [Document] = []
        if hasLiveServer {
            var query = DocumentQuery()
            query.customFieldID = field.id
            // Mehrere Seiten: Vorher nur die erste (250) — weitere Fristen fehlten still.
            for pageNumber in 1...8 {
                guard let page = try? await fetchPage(query: query, page: pageNumber, pageSize: 250,
                                                      ordering: "-created,-id") else { break }
                candidates.append(contentsOf: page.documents)
                guard page.hasNext else { break }
            }
        }
        if candidates.isEmpty {
            // Offline oder ohne Treffer: aus dem Zwischenspeicher.
            candidates = documents.filter { doc in
                doc.customFields.contains { $0.field == field.id && !$0.value.isEmpty }
            }
        }

        return Self.deadlineEntries(from: candidates, fieldId: field.id)
    }

    /// Die Fristen aus dem eigenen Feld, nach Datum sortiert. Ohne Store-Zugriff — auch für den
    /// Hintergrundlauf (`NotificationService`).
    nonisolated static func deadlineEntries(from documents: [Document], fieldId: Int) -> [DeadlineEntry] {
        documents.compactMap { doc -> DeadlineEntry? in
            guard let entry = doc.customFields.first(where: { $0.field == fieldId }),
                  case .text(let raw) = entry.value,
                  let date = DateFormatting.parseAPIDate(raw) else { return nil }
            return DeadlineEntry(document: doc, date: date)
        }
        .sorted { $0.date < $1.date }
    }

    /// Fristen, die in den nächsten Tagen fällig werden — für die Hintergrund-Benachrichtigung.
    func upcomingDeadlines(withinDays days: Int) async -> [DeadlineEntry] {
        let all = await loadDeadlines()
        return all.filter { $0.daysRemaining >= 0 && $0.daysRemaining <= days }
    }
}
