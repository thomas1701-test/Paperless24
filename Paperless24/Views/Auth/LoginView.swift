import SwiftUI

enum LoginMode {
    case initial
    case addAccount
}

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @Binding var useFaceID: Bool
    var mode: LoginMode = .initial
    let onConnect: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var serverUrl: String
    @State private var username: String
    @State private var password = ""
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var otpRequired = false
    @State private var otpCode = ""
    @State private var showDemoConfirm = false

    init(
        useFaceID: Binding<Bool>,
        mode: LoginMode = .initial,
        onConnect: @escaping () -> Void,
        prefillServerUrl: String = "",
        prefillUsername: String = ""
    ) {
        self._useFaceID = useFaceID
        self.mode = mode
        self.onConnect = onConnect
        self._serverUrl = State(initialValue: prefillServerUrl)
        self._username = State(initialValue: prefillUsername)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Login").font(.largeTitle).bold()
            TextField("Server", text: $serverUrl)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: serverUrl) { _, _ in resetOtp() }
            TextField("Benutzer", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: username) { _, _ in resetOtp() }
            SecureField("Passwort", text: $password)
                .textFieldStyle(.roundedBorder)
                .onChange(of: password) { _, _ in resetOtp() }
            if otpRequired {
                VStack(spacing: 4) {
                    Text("Gib deinen Authentifikator-Code ein")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("6-stelliger Code", text: $otpCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                }
            }
            if mode == .initial {
                Toggle("FaceID", isOn: $useFaceID)
            }
            if isChecking {
                ProgressView()
            } else {
                Button(otpRequired ? "Code bestätigen" : "Login") { login() }
                    .buttonStyle(.borderedProminent)
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red).font(.caption)
            }
            if mode == .initial {
                Button("Demo") { showDemoConfirm = true }
                    .foregroundColor(.orange)
                    .alert("Demo-Modus", isPresented: $showDemoConfirm) {
                        Button("Abbrechen", role: .cancel) {}
                        Button("Starten") { store.setupDemoData(); onConnect() }
                    } message: {
                        Text("Zeigt Beispieldaten. Es wird keine Verbindung zum Server hergestellt.")
                    }
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func resetOtp() {
        otpRequired = false
        otpCode = ""
    }

    private func login() {
        isChecking = true
        errorMessage = ""
        Task { @MainActor in
            do {
                if !otpRequired {
                    try await PaperlessAPI.checkConnection(
                        serverUrl: serverUrl,
                        username: username,
                        password: password
                    )
                }
                let token = try await PaperlessAPI.fetchToken(
                    serverUrl: serverUrl,
                    username: username,
                    password: password,
                    otp: otpRequired && !otpCode.isEmpty ? otpCode : nil
                )
                let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

                if mode == .addAccount {
                    if store.accounts.contains(where: {
                        $0.serverUrl == serverUrl && $0.username == username
                    }) {
                        errorMessage = String(localized: "account_already_exists")
                        isChecking = false
                        return
                    }
                }

                KeychainService.saveToken(cleanToken, for: serverUrl, username: username)
                store.isDemoMode = false

                if mode == .addAccount {
                    let account = Account(id: UUID(), serverUrl: serverUrl, username: username)
                    store.addAccount(account)
                    dismiss()
                } else {
                    let account = Account(id: UUID(), serverUrl: serverUrl, username: username)
                    store.addAccount(account)
                    onConnect()
                }
            } catch APIError.otpRequired {
                otpRequired = true
                errorMessage = ""
            } catch APIError.unauthorized {
                errorMessage = otpRequired ? String(localized: "wrong_otp_code") : String(localized: "login_failed")
            } catch {
                errorMessage = error.localizedDescription
            }
            isChecking = false
        }
    }
}
