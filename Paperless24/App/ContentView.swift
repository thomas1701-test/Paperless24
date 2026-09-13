import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.locale) private var locale
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @AppStorage("themeId") private var themeId = AppTheme.indigo.rawValue
    @AppStorage("customAccentHex") private var customAccentHex = "3F51B5"
    @AppStorage("amoledEnabled") private var amoledEnabled = false
    @Environment(\.colorScheme) private var systemScheme

    @State private var appState: AppState = .loading
    @State private var lastBackgroundTime: Date?
    @State private var isBlurry = false
    @State private var isAuthenticating = false
    /// Anmeldung abgebrochen oder fehlgeschlagen — die Sperre bleibt, mit Knopf zum erneuten Versuch.
    @State private var authFailed = false

    /// Aus den gespeicherten Werten abgeleitete Farben. Wird in die Umgebung gelegt,
    /// damit jede Ansicht `@Environment(\.palette)` nutzen kann.
    private var palette: ThemePalette {
        ThemeSettings(
            theme: AppTheme(rawValue: themeId) ?? .indigo,
            customAccentHex: customAccentHex,
            amoled: amoledEnabled
        )
        .palette(isDark: isDarkAppearance(mode: appearanceMode, system: systemScheme))
    }

    var body: some View {
        ZStack {
            if let surface = palette.surface {
                surface.ignoresSafeArea()
            }

            Group {
                switch appState {
                case .loading:  ProgressView()
                case .welcome:  WelcomeView(onStart: checkLogin)
                case .login:
                    LoginView(
                        useFaceID: $useFaceID,
                        onConnect: { appState = .main },
                        prefillServerUrl: store.serverUrl,
                        prefillUsername: store.username
                    )
                case .main:     RootTabView(onLogout: { appState = .login })
                }
            }
            .preferredColorScheme(appearanceMode == 1 ? .light : (appearanceMode == 2 ? .dark : nil))
            // Die Sperrfläche verdeckt den Inhalt nur optisch — VoiceOver las ihn darunter weiter vor.
            .accessibilityHidden(isBlurry)

            if isBlurry {
                Rectangle().fill(Material.ultraThin).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 60)).foregroundColor(.gray)
                    Text("Geschützt").font(.largeTitle).bold().foregroundColor(.gray)
                    if authFailed {
                        Button("Entsperren") { authenticate() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        // `tint` färbt Systemsteuerelemente, `palette` alles Selbstgezeichnete. Beides ist
        // nötig: `Color.accentColor` liest weiterhin das Asset und folgt `tint` nicht.
        .tint(palette.accent)
        .environment(\.palette, palette)
        .onAppear {
            ReviewRequestService.shared.registerLaunch()
            if store.serverUrl.isEmpty {
                appState = .welcome
            } else {
                checkLogin()
            }
        }
        .onChange(of: store.needsReLogin) { _, needs in
            if needs { store.needsReLogin = false; appState = .login }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if appState == .main && useFaceID {
                    let timedOut = lastBackgroundTime.map { Date().timeIntervalSince($0) > 60 } ?? false
                    // `authFailed` hält die Sperre auch über einen kurzen Wechsel hinweg —
                    // sonst ließe sie sich durch einmal Hoch- und Zurückwischen umgehen.
                    if timedOut || authFailed {
                        if !isAuthenticating { authenticate() }
                    } else {
                        withAnimation { isBlurry = false }
                    }
                } else if authFailed {
                    // Abbruch schon beim Kaltstart: `appState` steht noch auf `.loading`. Die
                    // Sperrfläche mit „Entsperren" muss stehen bleiben — vorher verschwand sie
                    // hier, und übrig blieb ein Ladekreis ohne Bedienmöglichkeit.
                    withAnimation { isBlurry = true }
                } else {
                    withAnimation { isBlurry = false }
                }
            case .background:
                withAnimation { isBlurry = true }
                lastBackgroundTime = Date()
            case .inactive:
                withAnimation { isBlurry = true }
            @unknown default:
                break
            }
        }
    }

    private func checkLogin() {
        guard !store.serverUrl.isEmpty else { appState = .login; return }
        guard store.hasValidToken() else { appState = .login; return }
        if useFaceID { authenticate() } else { appState = .main }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authFailed = false
        let context = LAContext()
        var error: NSError?

        // `.deviceOwnerAuthentication` statt `...WithBiometrics`: schlägt die Biometrie fehl
        // oder ist sie gesperrt (fünf Fehlversuche, kein Gesicht/Finger hinterlegt), fragt das
        // System nach dem Gerätecode. Vorher wurde in genau diesen Fällen ungeprüft entsperrt.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Das Gerät hat überhaupt keine Sperre eingerichtet — es gibt nichts zu prüfen.
            isAuthenticating = false
            withAnimation { isBlurry = false }
            appState = .main
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "biometric_reason", locale: locale)) { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.lastBackgroundTime = nil
                    self.authFailed = false
                    withAnimation { self.isBlurry = false }
                    self.appState = .main
                } else {
                    // Abgebrochen oder fehlgeschlagen: gesperrt bleiben, aber einen Weg zurück
                    // anbieten. Vorher blieb der Blur ohne jede Bedienmöglichkeit stehen.
                    self.authFailed = true
                    withAnimation { self.isBlurry = true }
                }
            }
        }
    }
}
