import SwiftUI

struct DocumentCard: View {
    let doc: Document
    let serverBase: String
    let token: String
    let allTags: [Tag]
    let allCorrespondents: [Correspondent]
    var allDocTypes: [DocumentType] = []
    var isSelected: Bool = false

    private var firstTagColor: Color {
        guard let firstTagId = doc.tags.first,
              let tag = allTags.first(where: { $0.id == firstTagId }) else {
            return Color(.systemGray4)
        }
        return Color(hex: tag.safeColor)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                let thumbUrl = "\(serverBase)/api/documents/\(doc.id)/thumb/"

                ZStack(alignment: .bottomTrailing) {
                    AuthImage(docId: doc.id, urlString: thumbUrl, token: token, contentMode: .fill)
                        .frame(height: 80)
                        .background(
                            LinearGradient(
                                colors: [firstTagColor.opacity(0.5), firstTagColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipped()

                    if !doc.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(doc.tags.prefix(2), id: \.self) { tagId in
                                if let tag = allTags.first(where: { $0.id == tagId }) {
                                    Text(tag.safeName)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color(hex: tag.safeColor))
                                        .cornerRadius(6)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(5)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    HStack {
                        if let cid = doc.correspondent, let name = allCorrespondents.first(where: { $0.id == cid })?.safeName {
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let date = doc.dateObject {
                            Text(date, style: .date)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let tid = doc.documentType, let typeName = allDocTypes.first(where: { $0.id == tid })?.safeName {
                        Text(typeName)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    } else {
                        Color.clear.frame(height: 16)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(height: 72)
            }
            .background(Material.thickMaterial)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))

            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor).padding(6)
            }
        }
    }
}
