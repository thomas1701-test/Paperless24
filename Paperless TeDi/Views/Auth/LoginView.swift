import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @Binding var useFaceID: Bool
    let onConnect: () -> Void

    @State private var password = ""
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var showDemoConfirm = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Login").font(.largeTitle).bold()
            TextField("Server", text: $store.serverUrl)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField("Benutzer", text: $store.username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            SecureField("Passwort", text: $password)
                .textFieldStyle(.roundedBorder)
            Toggle("FaceID", isOn: $useFaceID)

            if isChecking {
                ProgressView()
            } else {
                Button("Login") { login() }.buttonStyle(.borderedProminent)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red).font(.caption)
            }

            Button("Demo") { showDemoConfirm = true }
                .foregroundColor(.orange)
                .alert("Demo-Modus", isPresented: $showDemoConfirm) {
                    Button("Abbrechen", role: .cancel) {}
                    Button("Starten") { store.setupDemoData(); onConnect() }
                } message: {
                    Text("Zeigt Beispieldaten. Es wird keine Verbindung zum Server hergestellt.")
                }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func login() {
        isChecking = true
        errorMessage = ""
        Task {
            do {
                try await PaperlessAPI.checkConnection(serverUrl: store.serverUrl, username: store.username, password: password)
                let token = try await PaperlessAPI.fetchToken(serverUrl: store.serverUrl, username: store.username, password: password)
                KeychainService.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines), for: store.serverUrl)
                store.isDemoMode = false
                onConnect()
            } catch APIError.unauthorized {
                errorMessage = "Login fehlgeschlagen"
            } catch {
                errorMessage = error.localizedDescription
            }
            isChecking = false
        }
    }
}
