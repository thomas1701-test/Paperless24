import SwiftUI

struct SimpleInputSheet: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form { TextField("Name", text: $text) }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { onCancel() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Erstellen") { onSave() } }
                }
        }
        .presentationDetents([.height(200)])
    }
}
