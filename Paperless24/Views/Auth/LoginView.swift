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
    @Environment(\.locale) private var locale

    /// Eingabe ohne Schema — das Schema ergibt sich aus `allowHTTP`.
    @State private var serverUrl: String
    /// Standard ist `https`. `http` nur, wenn dieser Schalter ausdrücklich an ist.
    @State private var allowHTTP: Bool
    @State private var pastedHTTP = false
    @State private var username: String
    @State private var password = ""
    @State private var isChecking = false
    @State private var errorMessage = ""
    @State private var otpRequired = false
    @State private var otpCode = ""
    @State private var showDemoConfirm = false
    @State private var showServerAccess = false

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
        self._serverUrl = State(initialValue: ServerAddress.split(prefillServerUrl).rest)
        self._allowHTTP = State(initialValue: ServerAddress.initialScheme(for: prefillServerUrl) == .http)
        self._username = State(initialValue: prefillUsername)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Login").font(.largeTitle).bold()
            VStack(alignment: .leading, spacing: 8) {
                TextField("Server", text: $serverUrl)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .onChange(of: serverUrl) { _, new in
                        // Eingefügte Adresse mit Schema: Schema abtrennen. `https://` darf den
                        // Schalter zurücksetzen, `http://` schaltet ihn nicht ein — unverschlüsselt
                        // wird nur, wer es ausdrücklich wählt.
                        let parts = ServerAddress.split(new)
                        if let pasted = parts.scheme {
                            if pasted == .https { allowHTTP = false }
                            pastedHTTP = pasted == .http && !allowHTTP
                            serverUrl = parts.rest
                        }
                        resetOtp()
                    }
                Toggle("Unverschlüsselt verbinden (http)", isOn: $allowHTTP)
                    .font(.subheadline)
                    .onChange(of: allowHTTP) { _, on in
                        if on { pastedHTTP = false }
                        resetOtp()
                    }
                if allowHTTP {
                    Label("Passwort und Dokumente sind im Netzwerk mitlesbar. Nur im eigenen Netz verwenden.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if pastedHTTP {
                    Label("Die Adresse begann mit http://. Verbunden wird trotzdem verschlüsselt — für einen Server ohne HTTPS den Schalter einschalten.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Vor dem Login erreichbar: Wer hinter Cloudflare Access, Authelia oder einem
            // mTLS-Proxy steht, kommt ohne Kopfzeilen bzw. Zertifikat gar nicht bis zum Token.
            Button {
                showServerAccess = true
            } label: {
                Label("Serverzugang (Proxy, Zertifikat)", systemImage: "lock.shield")
                    .font(.caption)
            }
            .disabled(fullServerUrl.isEmpty)
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
        .sheet(isPresented: $showServerAccess) {
            NavigationStack {
                ServerAccessView(server: PaperlessAPI.normalizedBase(fullServerUrl), dismissAfterSave: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showServerAccess = false }
                        }
                    }
            }
            .environmentObject(store)
        }
    }

    /// Adresse mit Schema. Gibt es das Konto schon, dessen gespeicherte Schreibweise.
    private var fullServerUrl: String {
        let composed = ServerAddress.compose(scheme: allowHTTP ? .http : .https, input: serverUrl)
        return ServerAddress.storedSpelling(
            of: composed, username: username,
            accounts: store.accounts.map { ($0.serverUrl, $0.username) }
        ) ?? composed
    }

    private func resetOtp() {
        otpRequired = false
        otpCode = ""
    }

    private func login() {
        isChecking = true
        errorMessage = ""
        let serverUrl = fullServerUrl
        Task { @MainActor in
            do {
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
                        errorMessage = String(localized: "account_already_exists", locale: locale)
                        isChecking = false
                        return
                    }
                }

                // Ohne diese Prüfung meldete die App „angemeldet", obwohl der Token gar nicht
                // im Keychain gelandet ist — der nächste Sync lief dann in „Sitzung abgelaufen".
                guard KeychainService.saveToken(cleanToken, for: serverUrl, username: username) else {
                    errorMessage = String(localized: "keychain_save_failed", locale: locale)
                    isChecking = false
                    return
                }
                store.invalidateTokenCache()
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
                errorMessage = otpRequired ? String(localized: "wrong_otp_code", locale: locale) : String(localized: "login_failed", locale: locale)
            } catch {
                errorMessage = error.localizedDescription
            }
            isChecking = false
        }
    }
}
