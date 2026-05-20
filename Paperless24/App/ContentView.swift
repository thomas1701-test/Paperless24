import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("appearanceMode") private var appearanceMode = 0

    @State private var appState: AppState = .loading
    @State private var lastBackgroundTime: Date?
    @State private var isBlurry = false
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
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

            if isBlurry {
                Rectangle().fill(Material.ultraThin).ignoresSafeArea()
                VStack {
                    Image(systemName: "lock.shield.fill").font(.system(size: 60)).foregroundColor(.gray)
                    Text("Geschützt").font(.largeTitle).bold().foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            if store.serverUrl.isEmpty {
                appState = .welcome
            } else {
                checkLogin()
            }
        }
        .onChange(of: store.needsReLogin) { needs in
            if needs { store.needsReLogin = false; appState = .login }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if appState == .main && useFaceID {
                    if let last = lastBackgroundTime, Date().timeIntervalSince(last) > 60 {
                        if !isAuthenticating { authenticate() }
                    } else {
                        withAnimation { isBlurry = false }
                    }
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
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: String(localized: "biometric_reason")) { success, _ in
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    if success {
                        self.lastBackgroundTime = nil
                        withAnimation { self.isBlurry = false }
                        self.appState = .main
                    }
                }
            }
        } else {
            isAuthenticating = false
            withAnimation { isBlurry = false }
            appState = .main
        }
    }
}
