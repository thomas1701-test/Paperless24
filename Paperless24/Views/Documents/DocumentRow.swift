import SwiftUI

struct DocumentRow: View {
    let doc: Document
    let allTags: [Tag]
    let allCorrespondents: [Correspondent]
    var serverBase: String = ""
    var token: String = ""

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
                HStack {
                    if let cid = doc.correspondent, let name = allCorrespondents.first(where: { $0.id == cid })?.safeName {
                        Text(name).font(.caption).foregroundColor(.secondary)
                        Text("•").font(.caption).foregroundColor(.secondary)
                    }
                    Text(doc.created).font(.caption).foregroundColor(.secondary)
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
