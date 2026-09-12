import SwiftUI

/// Posteingang „durchwischen".
///
/// Ein Dokument pro Bildschirm: Vorschau oben, darunter Sender, Typ und Tags — vorbelegt mit
/// den Vorschlägen des Servers (`/api/documents/{id}/suggestions/`). Bestätigen nimmt das
/// Dokument aus dem Posteingang und legt das nächste vor.
///
/// Vorher brauchte derselbe Vorgang pro Dokument: antippen, Bearbeiten öffnen, drei Blätter
/// durchklicken, Inbox-Tag von Hand abwählen, speichern, zurück.
struct TriageView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// Eigene Kopie: Der Posteingang im Store schrumpft mit jedem erledigten Dokument,
    /// eine Ansicht über `store.inboxDocuments` würde beim Bestätigen unter dem Finger
    /// weghüpfen.
    @State private var queue: [Document] = []
    @State private var index = 0

    @State private var title = ""
    @State private var date = Date()
    @State private var correspondent: Int? = nil
    @State private var documentType: Int? = nil
    @State private var tags: [Int] = []

    @State private var suggestions: DocumentSuggestions? = nil
    @State private var isLoadingSuggestions = false
    @State private var showCorrPicker = false
    @State private var showTypePicker = false
    @State private var showTagPicker = false
    @State private var tagSelection = Set<Int>()
    @State private var doneCount = 0
    /// Im Text belegte Frist — wird erst mit dem Häkchen gespeichert.
    @State private var deadline: Deadline? = nil
    @State private var acceptDeadline = true

    private var current: Document? { index < queue.count ? queue[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if let doc = current {
                    content(for: doc)
                } else {
                    finished
                }
            }
            .navigationTitle(current == nil ? "Fertig" : "\(index + 1) von \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface(palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                if current != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Überspringen") { advance() }
                    }
                }
            }
        }
        .onAppear(perform: start)
        .sheet(isPresented: $showCorrPicker) {
            FilterPickerSheet(
                title: "Sender",
                items: store.allCorrespondents.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                noneLabel: "Keiner",
                selectedId: $correspondent
            )
        }
        .sheet(isPresented: $showTypePicker) {
            FilterPickerSheet(
                title: "Typ",
                items: store.allDocTypes.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                noneLabel: "Keiner",
                selectedId: $documentType
            )
        }
        .sheet(isPresented: $showTagPicker, onDismiss: { tags = Array(tagSelection) }) {
            MultiSelectPickerSheet(
                title: "Tags",
                items: store.allTags.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                colors: Dictionary(store.allTags.map { ($0.id, $0.safeColor) }, uniquingKeysWith: { a, _ in a }),
                selected: $tagSelection
            )
        }
    }

    // MARK: - Ein Dokument

    private func content(for doc: Document) -> some View {
        VStack(spacing: 0) {
            AuthImage(docId: doc.id, urlString: store.thumbnailURL(for: doc.id),
                      token: store.authToken(), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .background(Color(.secondarySystemBackground))

            Form {
                Section {
                    TextField("Titel", text: $title)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }

                Section {
                    pickerRow("Sender", systemImage: "person",
                              value: correspondent.flatMap { id in store.allCorrespondents.first { $0.id == id }?.safeName },
                              suggested: suggestedCorrespondentName) { showCorrPicker = true }
                    pickerRow("Typ", systemImage: "doc.text",
                              value: documentType.flatMap { id in store.allDocTypes.first { $0.id == id }?.safeName },
                              suggested: suggestedTypeName) { showTypePicker = true }
                    pickerRow("Tags", systemImage: "tag",
                              value: tags.isEmpty ? nil : "\(tags.count) gewählt",
                              suggested: suggestedTagNames) { tagSelection = Set(tags); showTagPicker = true }
                } header: {
                    HStack {
                        Text("Zuordnung")
                        if isLoadingSuggestions {
                            ProgressView().controlSize(.mini).padding(.leading, 4)
                        }
                    }
                } footer: {
                    if let s = suggestions, !s.isEmpty {
                        Text("Vorbelegt aus den Vorschlägen des Servers.")
                    }
                }

                if let deadline {
                    Section {
                        Toggle(isOn: $acceptDeadline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("\(deadline.kind.label): \(deadline.date.formatted(date: .abbreviated, time: .omitted))",
                                      systemImage: deadline.kind.symbolName)
                                Text(deadline.evidence)
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                    } header: {
                        Text("Frist erkannt")
                    } footer: {
                        Text("Wird als Datum im Feld \u{201E}Fälligkeit\u{201C} gespeichert.")
                    }
                }

                Section {
                    Button {
                        confirm(doc)
                    } label: {
                        Label("Erledigt und weiter", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60)).foregroundColor(.green)
            Text(doneCount > 0 ? "\(doneCount) Dokument(e) abgearbeitet" : "Nichts zu tun")
                .font(.title3)
            Button("Schließen") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pickerRow(_ title: String, systemImage: String, value: String?,
                           suggested: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value ?? "—").foregroundColor(value == nil ? .secondary : .primary)
                    // Der Vorschlag bleibt sichtbar, auch wenn er schon übernommen wurde —
                    // sonst weiß man nicht, was vom Server kam und was man selbst gesetzt hat.
                    if let suggested, suggested != value {
                        Text(suggested)
                            .font(.caption2)
                            .foregroundColor(palette.accent)
                    }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
        }
        .foregroundColor(.primary)
    }

    // MARK: - Vorschlagsnamen

    private var suggestedCorrespondentName: String? {
        guard let id = suggestions?.correspondents.first else { return nil }
        return store.allCorrespondents.first { $0.id == id }?.safeName
    }

    private var suggestedTypeName: String? {
        guard let id = suggestions?.documentTypes.first else { return nil }
        return store.allDocTypes.first { $0.id == id }?.safeName
    }

    private var suggestedTagNames: String? {
        guard let ids = suggestions?.tags, !ids.isEmpty else { return nil }
        let names = ids.compactMap { id in store.allTags.first { $0.id == id }?.safeName }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // MARK: - Ablauf

    private func start() {
        guard queue.isEmpty else { return }
        queue = store.inboxDocuments
        index = 0
        load(current)
    }

    private func load(_ doc: Document?) {
        suggestions = nil
        deadline = nil
        guard let doc else { return }
        title = doc.title
        date = doc.dateObject ?? Date()
        correspondent = doc.correspondent
        documentType = doc.documentType
        // Die Inbox-Tags gehören nicht in die Auswahl: Sie werden beim Bestätigen entfernt,
        // und sie als Vorschlag anzuzeigen wäre irreführend.
        tags = doc.tags.filter { !store.inboxTagIDs.contains($0) }

        // Frist aus dem Text — hier ist die Stelle, an der der Nutzer ohnehin hinsieht.
        acceptDeadline = true
        deadline = store.isDeadlineRadarEnabled
            ? DeadlineDetector.primaryDeadline(in: doc.content ?? "", documentId: doc.id)
            : nil

        Task {
            isLoadingSuggestions = true
            let result = await store.fetchSuggestions(for: doc.id)
            // Nur übernehmen, wenn der Nutzer noch bei demselben Dokument ist.
            guard current?.id == doc.id else { isLoadingSuggestions = false; return }
            suggestions = result
            applySuggestions(result, to: doc)
            isLoadingSuggestions = false
        }
    }

    /// Vorschläge füllen nur *leere* Felder. Was am Dokument schon steht, ist eine Entscheidung
    /// und wird nicht überschrieben.
    private func applySuggestions(_ s: DocumentSuggestions?, to doc: Document) {
        guard let s else { return }
        if correspondent == nil { correspondent = s.correspondents.first }
        if documentType == nil { documentType = s.documentTypes.first }
        if tags.isEmpty { tags = s.tags }
        if doc.dateObject == nil, let suggested = s.suggestedDate { date = suggested }
    }

    private func confirm(_ doc: Document) {
        let inboxIDs = store.inboxTagIDs
        // Der Inbox-Tag fliegt raus — das ist der Abschluss des Vorgangs.
        let finalTags = tags.filter { !inboxIDs.contains($0) }

        // Die Frist in einem Zug mitschreiben, statt zwei Änderungen in die Warteschlange zu
        // legen, von denen die zweite die erste überschreibt.
        var fields = doc.customFields
        if acceptDeadline, let deadline, let field = store.deadlineField {
            fields.removeAll { $0.field == field.id }
            fields.append(CustomFieldEdit(field: field.id,
                                          value: .text(DateFormatting.apiDate(deadline.date))))
        }
        store.addPendingEdit(docId: doc.id, title: title, created: date,
                             corr: correspondent, type: documentType,
                             asn: doc.archiveSerialNumber, tags: finalTags,
                             customFields: fields)
        // Fehlt das Feld noch, wird es angelegt und die Frist danach nachgetragen.
        if acceptDeadline, let deadline, store.deadlineField == nil {
            Task { await store.confirmDeadline(deadline) }
        }
        store.inboxDocuments.removeAll { $0.id == doc.id }
        if let total = store.inboxTotal { store.inboxTotal = max(0, total - 1) }
        doneCount += 1
        store.haptic(.medium)
        advance()
    }

    private func advance() {
        index += 1
        load(current)
    }
}
