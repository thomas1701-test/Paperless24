import SwiftUI

struct DocumentRow: View {
    let doc: Document
    let allTags: [Tag]
    let allCorrespondents: [Correspondent]

    var body: some View {
        HStack {
            Image(systemName: "doc.text.fill").font(.largeTitle).foregroundColor(.blue).padding(.trailing, 5)

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
