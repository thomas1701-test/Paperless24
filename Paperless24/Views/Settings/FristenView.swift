import SwiftUI

/// Fristen-Radar: erkannte Termine, Erinnerungen, Kündigungs-Entwürfe.
struct FristenView: View {
    @EnvironmentObject var store: AppStore

    @State private var draftText: String = ""
    @State private var showDraft = false
    @State private var draftingId: UUID?
    @State private var toast: String?
    @State private var openDoc: Document?

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let items: [Deadline]
    }

    private var sections: [Section] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekEnd = cal.date(byAdding: .day, value: 7, to: today)!
        let monthEnd = cal.date(byAdding: .day, value: 31, to: today)!
        var overdue: [Deadline] = [], week: [Deadline] = [], month: [Deadline] = [], later: [Deadline] = []
        for d in store.deadlines.sorted(by: { $0.date < $1.date }) {
            if d.date < today { overdue.append(d) }
            else if d.date <= weekEnd { week.append(d) }
            else if d.date <= monthEnd { month.append(d) }
            else { later.append(d) }
        }
        return [
            Section(title: "Überfällig", items: overdue),
            Section(title: "Diese Woche", items: week),
            Section(title: "Dieser Monat", items: month),
            Section(title: "Später", items: later)
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        List {
            if store.isScanningDeadlines {
                HStack { ProgressView(); Text(store.deadlineScanStatus).foregroundColor(.secondary) }
            }
            if store.deadlines.isEmpty && !store.isScanningDeadlines {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 44)).foregroundColor(.gray)
                    Text("Noch keine Fristen erkannt").foregroundColor(.gray)
                    if !AIService.shared.isAvailable {
                        Text("Benötigt aktivierte KI-Funktionen.").font(.caption).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            ForEach(sections) { section in
                SwiftUI.Section(section.title) {
                    ForEach(section.items) { d in row(d) }
                }
            }
        }
        .navigationTitle("Fristen-Radar")
        .toolbar {
            Button {
                store.scanAllForDeadlines()
            } label: { Image(systemName: "sparkles.rectangle.stack") }
            .disabled(store.isScanningDeadlines || !AIService.shared.isAvailable)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).padding().background(Color.green).foregroundColor(.white)
                    .cornerRadius(10).padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showDraft) {
            NavigationView {
                ScrollView { Text(draftText).padding().frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("Kündigungsentwurf")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            ShareLink(item: draftText) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
            }
        }
        .sheet(item: $openDoc) { doc in
            NavigationView {
                DocumentDetailView(doc: doc,
                                   onSave: { _, _, _, _, _, _, _, _ in },
                                   onDelete: { store.deleteDocument(id: $0); openDoc = nil })
            }
        }
    }

    private func openDocument(_ d: Deadline) {
        if let doc = store.documents.first(where: { $0.id == d.docId }) {
            openDoc = doc
        } else {
            Task { openDoc = await store.fetchDocumentDetail(id: d.docId) }
        }
    }

    @ViewBuilder
    private func row(_ d: Deadline) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                openDocument(d)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: d.type.icon).foregroundColor(d.type.color)
                        Text(d.type.label).font(.caption).fontWeight(.semibold).foregroundColor(d.type.color)
                        Spacer()
                        Text(d.date, style: .date).font(.caption).foregroundColor(.secondary)
                    }
                    HStack {
                        Text(d.docTitle).font(.subheadline).lineLimit(1).foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    }
                    if !d.detail.isEmpty {
                        Text(d.detail).font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
            HStack {
                Button {
                    Task { await addReminder(d) }
                } label: { Label("Erinnerung", systemImage: "bell") }
                    .buttonStyle(.bordered).controlSize(.small)
                if d.type == .cancellation {
                    Button {
                        Task { await draft(d) }
                    } label: {
                        HStack {
                            if draftingId == d.id { ProgressView().controlSize(.mini) }
                            Label("Kündigung entwerfen", systemImage: "doc.badge.plus")
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.orange)
                    .disabled(draftingId != nil || !AIService.shared.isAvailable)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) { store.removeDeadline(d.id) } label: { Label("Entfernen", systemImage: "trash") }
        }
    }

    private func addReminder(_ d: Deadline) async {
        let ok = await EventKitService.addReminder(
            title: "\(d.type.label): \(d.docTitle)", due: d.date, notes: d.detail)
        showToast(ok ? "Erinnerung erstellt" : "Erinnerung fehlgeschlagen")
    }

    private func draft(_ d: Deadline) async {
        draftingId = d.id
        if let text = await store.draftCancellation(for: d) {
            draftText = text
            showDraft = true
        } else {
            showToast("Entwurf nicht möglich")
        }
        draftingId = nil
    }

    private func showToast(_ msg: String) {
        toast = msg
        Task { try? await Task.sleep(nanoseconds: 2_500_000_000); toast = nil }
    }
}
