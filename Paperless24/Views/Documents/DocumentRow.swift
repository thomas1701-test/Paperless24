import SwiftUI

struct DocumentRow: View {
    let doc: Document
    let allTags: [Tag]
    let allCorrespondents: [Correspondent]
    var serverBase: String = ""
    var token: String = ""
    var allDocTypes: [DocumentType] = []
    /// Suchbegriff der laufenden Suche. Gesetzt heißt: Textausschnitt statt Metadatenzeile.
    var searchQuery: String = ""

    // Welche Angaben in der Zeile stehen, entscheidet der Nutzer in den Einstellungen.
    // Vorher war die Zeile fest auf Sender + Belegdatum verdrahtet; wer nach ASN oder
    // Hinzugefügt-Datum arbeitet, sah gerade das nicht.
    @AppStorage("rowShowCorrespondent") private var showCorrespondent = true
    @AppStorage("rowShowDate") private var showDate = true
    @AppStorage("rowShowType") private var showType = false
    @AppStorage("rowShowASN") private var showASN = false
    @AppStorage("rowShowAdded") private var showAdded = false

    /// Die sichtbaren Angaben in der Reihenfolge, in der sie gezeigt werden.
    private var metadataParts: [String] {
        var parts: [String] = []
        if showCorrespondent, let cid = doc.correspondent,
           let name = allCorrespondents.first(where: { $0.id == cid })?.safeName {
            parts.append(name)
        }
        if showType, let tid = doc.documentType,
           let name = allDocTypes.first(where: { $0.id == tid })?.safeName {
            parts.append(name)
        }
        if showDate, !doc.created.isEmpty { parts.append(String(doc.created.prefix(10))) }
        if showAdded, let added = doc.added, !added.isEmpty {
            parts.append("+ " + String(added.prefix(10)))
        }
        if showASN, let asn = doc.archiveSerialNumber { parts.append("ASN \(asn)") }
        return parts
    }

    var body: some View {
        HStack(spacing: 10) {
            if !serverBase.isEmpty && !token.isEmpty {
                AuthImage(
                    docId: doc.id,
                    urlString: "\(serverBase)/api/documents/\(doc.id)/thumb/",
                    token: token,
                    contentMode: .fill
                )
                .frame(width: 44, height: 56)
                .cornerRadius(6)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 56)
                    .overlay(Image(systemName: "doc.text").foregroundColor(.gray))
            }


            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).font(.headline).lineLimit(1)
                if !metadataParts.isEmpty {
                    Text(metadataParts.joined(separator: " • "))
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                // Bei einer Suche zählt die Stelle, an der der Begriff steht — nicht das
                // Datum. Der Ausschnitt kommt vom Server, sonst aus dem erkannten Text.
                if let snippet = doc.searchSnippet(for: searchQuery), !searchQuery.isEmpty {
                    Text(snippet)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()

            if !doc.tags.isEmpty {
                HStack(spacing: -4) {
                    ForEach(doc.tags.prefix(3), id: \.self) { tagId in
                        if let tag = allTags.first(where: { $0.id == tagId }) {
                            Circle()
                                .fill(Color(hex: tag.safeColor))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
