import SwiftUI

struct DashboardItem: View {
    /// `LocalizedStringKey` statt `String` — als `String` landete der deutsche Literal
    /// ungeprüft auf dem Bildschirm, die Kacheln blieben in jeder Sprache deutsch.
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.title2).foregroundColor(color)
                Spacer()
                Text(value).font(.title2).bold().foregroundColor(.primary)
            }
            Text(title).font(.subheadline).foregroundColor(.secondary)
        }
        .padding()
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
    }
}
