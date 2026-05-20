import SwiftUI

struct AccountsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.locale) private var locale
    @State private var showAddAccount = false
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteConfirm = false
    @State private var showLastAccountAlert = false

    var body: some View {
        List {
            ForEach(store.accounts) { account in
                Button {
                    if account.id != store.activeAccountId {
                        store.switchAccount(to: account.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username).font(.headline)
                            Text(account.serverUrl).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if account.id == store.activeAccountId {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
            .onDelete { offsets in
                guard let first = offsets.first else { return }
                let account = store.accounts[first]
                guard store.accounts.count > 1 else {
                    showLastAccountAlert = true
                    return
                }
                accountToDelete = account
                showDeleteConfirm = true
            }

            Button {
                showAddAccount = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus")
            }
        }
        .navigationTitle("Konten")
        .sheet(isPresented: $showAddAccount) {
            LoginView(useFaceID: .constant(false), mode: .addAccount, onConnect: {})
                .environmentObject(store)
        }
        .alert("Konto löschen", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) { accountToDelete = nil }
            Button("Löschen", role: .destructive) {
                if let account = accountToDelete {
                    store.removeAccount(id: account.id)
                }
                accountToDelete = nil
            }
        } message: {
            if let account = accountToDelete {
                Text(verbatim: String(format: String(localized: "delete_account_fmt", locale: locale), account.username, account.serverUrl))
            }
        }
        .alert("Letztes Konto", isPresented: $showLastAccountAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Das letzte Konto kann nicht gelöscht werden. Melde dich stattdessen ab.")
        }
    }
}
