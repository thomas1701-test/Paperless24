import SwiftUI

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text.image").font(.system(size: 80)).foregroundColor(.blue)
            Text("Paperless 24").font(.largeTitle).bold()
            Button("Starten", action: onStart).buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}
