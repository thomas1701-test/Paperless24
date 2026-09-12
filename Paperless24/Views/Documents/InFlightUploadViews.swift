import SwiftUI

/// Platzhalter für ein Dokument, das noch unterwegs ist.
///
/// Bisher verschwand ein Upload nach dem Absenden aus dem Blick: Ein schmaler Balken am
/// unteren Rand zählte „2 Uploads ausstehend", und irgendwann tauchte das Dokument in der
/// Liste auf. Dazwischen lag eine Lücke, in der nichts zu sehen war — und genau in dieser
/// Lücke wirkt eine App unzuverlässig. Der Platzhalter steht deshalb dort, wo das fertige
/// Dokument gleich stehen wird.
struct InFlightUploadRow: View {
    @Environment(\.palette) private var palette
    let item: AppStore.InFlightUpload
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray6))
                    .frame(width: 44, height: 56)
                Image(systemName: item.isProblem ? "exclamationmark.triangle.fill" : "arrow.up.doc")
                    .foregroundColor(item.isProblem ? .orange : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    if !item.isProblem {
                        ProgressView().controlSize(.mini)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(item.isProblem ? .orange : .secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if item.isProblem {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isProblem ? 1 : 0.75)
    }

    private var statusText: String {
        if let detail = item.detail, !detail.isEmpty { return detail }
        switch item.phase {
        case .queued:     return String(localized: "Wird hochgeladen …")
        case .processing: return String(localized: "Wird auf dem Server verarbeitet …")
        case .failed:     return String(localized: "Nicht verarbeitet")
        case .duplicate:  return String(localized: "Schon im Archiv")
        }
    }
}

/// Dasselbe als Kachel fürs Raster.
struct InFlightUploadCard: View {
    @Environment(\.palette) private var palette
    let item: AppStore.InFlightUpload
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(height: 110)
                VStack(spacing: 8) {
                    if item.isProblem {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2).foregroundColor(.orange)
                    } else {
                        ProgressView()
                    }
                }
            }
            Text(item.title).font(.subheadline).lineLimit(1)
            Text(statusText)
                .font(.caption2)
                .foregroundColor(item.isProblem ? .orange : .secondary)
                .lineLimit(2)
            if item.isProblem {
                Button("Ausblenden", action: onDismiss)
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(palette.accent)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .opacity(item.isProblem ? 1 : 0.8)
    }

    private var statusText: String {
        if let detail = item.detail, !detail.isEmpty { return detail }
        switch item.phase {
        case .queued:     return String(localized: "Wird hochgeladen …")
        case .processing: return String(localized: "Wird verarbeitet …")
        case .failed:     return String(localized: "Nicht verarbeitet")
        case .duplicate:  return String(localized: "Schon im Archiv")
        }
    }
}
