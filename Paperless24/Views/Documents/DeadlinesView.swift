import SwiftUI

/// „Was steht an" — bestätigte Fristen und belegbare Vorschläge.
struct DeadlinesView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @State private var entries: [DeadlineEntry] = []
    @State private var suggestions: [Deadline] = []
    @State private var isLoading = false
    @State private var message: String? = nil
    @State private var openDoc: Document? = nil

    var body: some View {
        List {
            if store.deadlineField == nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kein Fristenfeld").font(.headline)
                        Text("Fristen werden in einem eigenen Feld auf dem Server gespeichert — "
                             + "so stehen sie auch in der Weboberfläche und auf anderen Geräten.")
                            .font(.caption).foregroundColor(.secondary)
                        Button("Feld „Fälligkeit\u{201C} anlegen") {
                            Task {
                                if await store.ensureDeadlineField() != nil { await reload() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }
                }
            }

            ForEach(Bucket.allCases, id: \.self) { bucket in
                let items = entries.filter { bucket.contains($0.daysRemaining) }
                if !items.isEmpty {
                    Section(bucket.title) {
                        ForEach(items) { entry in
                            row(entry)
                        }
                    }
                }
            }

            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                } header: {
                    Text("Vorschläge")
                } footer: {
                    Text("Gefunden im Text der geladenen Dokumente. Erst mit „Übernehmen\u{201C} "
                         + "wird die Frist gespeichert.")
                }
            }

            if entries.isEmpty && suggestions.isEmpty && !isLoading && store.deadlineField != nil {
                Section {
                    Text(store.isDeadlineRadarEnabled
                         ? "Keine Fristen gefunden."
                         : "Das Fristen-Radar ist in den Einstellungen abgeschaltet.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .themedSurface(palette)
        .navigationTitle("Fristen")
        .overlay {
            if isLoading && entries.isEmpty { ProgressView() }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .alert("Hinweis", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .navigationDestination(item: $openDoc) { doc in
            DocumentDetailView(doc: doc,
                               onSave: { id, title, date, corr, type, asn, tags, fields in
                                   store.addPendingEdit(docId: id, title: title, created: date,
                                                        corr: corr, type: type, asn: asn,
                                                        tags: tags, customFields: fields)
                               },
                               onDelete: { store.deleteDocument(id: $0) })
        }
    }

    // MARK: - Zeilen

    private func row(_ entry: DeadlineEntry) -> some View {
        Button { openDoc = entry.document } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.document.title).lineLimit(1).foregroundColor(.primary)
                    Text(dueText(entry))
                        .font(.caption)
                        .foregroundColor(entry.isOverdue ? .red : .secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.clearDeadline(for: entry.document.id)
                entries.removeAll { $0.id == entry.id }
            } label: { Label("Frist löschen", systemImage: "xmark") }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await remind(entry) }
            } label: { Label("Erinnern", systemImage: "bell") }
            .tint(.orange)
        }
    }

    private func suggestionRow(_ suggestion: Deadline) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(suggestion.kind.label, systemImage: suggestion.kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(palette.accent)
                Spacer()
                Text(DateFormatting.apiDate(suggestion.date)).font(.caption).foregroundColor(.secondary)
            }
            Text(title(for: suggestion.documentId)).font(.subheadline).lineLimit(1)
            // Die Belegstelle macht prüfbar, was erkannt wurde — ohne sie müsste man dem
            // Vorschlag blind glauben.
            Text(suggestion.evidence)
                .font(.caption2).foregroundColor(.secondary).lineLimit(2)
            Button("Übernehmen") {
                Task {
                    if await store.confirmDeadline(suggestion) {
                        suggestions.removeAll { $0.id == suggestion.id }
                        await reload()
                    } else {
                        message = "Die Frist konnte nicht gespeichert werden."
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Hilfen

    private func title(for docId: Int) -> String {
        store.documents.first { $0.id == docId }?.title ?? "Dokument \(docId)"
    }

    private func dueText(_ entry: DeadlineEntry) -> String {
        let days = entry.daysRemaining
        let date = entry.date.formatted(date: .abbreviated, time: .omitted)
        if days < 0 { return "\(date) — seit \(-days) Tag(en) überfällig" }
        if days == 0 { return "\(date) — heute fällig" }
        return "\(date) — in \(days) Tag(en)"
    }

    private func reload() async {
        isLoading = true
        entries = await store.loadDeadlines()
        suggestions = store.deadlineSuggestions()
        isLoading = false
    }

    private func remind(_ entry: DeadlineEntry) async {
        do {
            try await RemindersService.addReminder(
                title: entry.document.title,
                dueDate: entry.date,
                notes: "Frist aus Paperless 24",
                leadDays: Deadline.Kind.payment.reminderLeadDays
            )
            message = "Erinnerung angelegt."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Zeitfenster für die Gruppierung.
    private enum Bucket: CaseIterable, Hashable {
        case overdue, today, week, month, later

        var title: String {
            switch self {
            case .overdue: return "Überfällig"
            case .today:   return "Heute"
            case .week:    return "Diese Woche"
            case .month:   return "Dieser Monat"
            case .later:   return "Später"
            }
        }

        func contains(_ days: Int) -> Bool {
            switch self {
            case .overdue: return days < 0
            case .today:   return days == 0
            case .week:    return days >= 1 && days <= 7
            case .month:   return days >= 8 && days <= 31
            case .later:   return days > 31
            }
        }
    }
}
