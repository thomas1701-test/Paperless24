import SwiftUI

/// Besitzer und Rechte für die ausgewählten Dokumente.
///
/// Nur sinnvoll, wenn mehrere Personen dieselbe Instanz nutzen — und nur dann bekommt die App
/// vom Server überhaupt eine Benutzerliste. Ist sie leer, fehlt entweder die Berechtigung oder
/// es gibt schlicht nur ein Konto; in beiden Fällen ist hier nichts zu entscheiden.
struct PermissionsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let documentIds: Set<Int>

    @State private var owner: Int? = nil
    @State private var viewUsers = Set<Int>()
    @State private var changeUsers = Set<Int>()
    @State private var viewGroups = Set<Int>()
    @State private var changeGroups = Set<Int>()
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Lade Benutzer …")
                } else if store.serverUsers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.slash").font(.largeTitle).foregroundColor(.secondary)
                        Text("Keine Benutzerliste verfügbar.")
                        Text("Der Server gibt sie nur Administratoren heraus.")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    form
                }
            }
            .navigationTitle("Rechte")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface(palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anwenden") {
                        store.assignPermissions(
                            owner: owner,
                            viewUsers: Array(viewUsers), viewGroups: Array(viewGroups),
                            changeUsers: Array(changeUsers), changeGroups: Array(changeGroups),
                            to: documentIds
                        )
                        dismiss()
                    }
                    .disabled(store.serverUsers.isEmpty)
                }
            }
            .task {
                await store.syncServerMetadata()
                isLoading = false
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Besitzer", selection: $owner) {
                    Text("Unverändert lassen").tag(Int?.none)
                    ForEach(store.serverUsers) { user in
                        Text(user.displayName).tag(Int?.some(user.id))
                    }
                }
            } footer: {
                Text("Gilt für \(documentIds.count) Dokument(e).")
            }

            Section("Ansehen dürfen") {
                userToggles(selection: $viewUsers)
                groupToggles(selection: $viewGroups)
            }

            Section {
                userToggles(selection: $changeUsers)
                groupToggles(selection: $changeGroups)
            } header: {
                Text("Bearbeiten dürfen")
            } footer: {
                Text("Der Server ersetzt die bestehenden Rechte durch diese Auswahl — es ist "
                     + "keine Ergänzung. Wer niemanden auswählt, macht die Dokumente privat.")
            }
        }
    }

    private func userToggles(selection: Binding<Set<Int>>) -> some View {
        ForEach(store.serverUsers) { user in
            Toggle(user.displayName, isOn: Binding(
                get: { selection.wrappedValue.contains(user.id) },
                set: { on in
                    if on { selection.wrappedValue.insert(user.id) }
                    else { selection.wrappedValue.remove(user.id) }
                }
            ))
        }
    }

    @ViewBuilder
    private func groupToggles(selection: Binding<Set<Int>>) -> some View {
        ForEach(store.serverGroups) { group in
            Toggle(isOn: Binding(
                get: { selection.wrappedValue.contains(group.id) },
                set: { on in
                    if on { selection.wrappedValue.insert(group.id) }
                    else { selection.wrappedValue.remove(group.id) }
                }
            )) {
                Label(group.safeName, systemImage: "person.3")
            }
        }
    }
}
