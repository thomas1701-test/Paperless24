import SwiftUI

struct DocumentCard: View {
    let doc: Document
    let serverBase: String
    let token: String
    let allTags: [Tag]
    let allCorrespondents: [Correspondent]
    var isSelected: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                let thumbUrl = "\(serverBase)/api/documents/\(doc.id)/thumb/"

                ZStack(alignment: .bottomTrailing) {
                    AuthImage(docId: doc.id, urlString: thumbUrl, token: token, contentMode: .fit)
                        .frame(height: 140)
                        .background(Color.white)
                        .clipped()

                    if !doc.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(doc.tags.prefix(3), id: \.self) { tagId in
                                if let tag = allTags.first(where: { $0.id == tagId }) {
                                    Text(tag.safeName)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color(hex: tag.safeColor))
                                        .cornerRadius(8)
                                        .shadow(radius: 1)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.title).font(.headline).lineLimit(2)
                    if let cid = doc.correspondent, let name = allCorrespondents.first(where: { $0.id == cid })?.safeName {
                        Text(name).font(.caption).foregroundColor(.blue).lineLimit(1)
                    }
                }
                .padding(8)
                .frame(height: 70, alignment: .top)
            }
            .background(Material.thickMaterial)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3))

            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue).padding(8)
            }
        }
        .frame(height: 210)
    }
}
