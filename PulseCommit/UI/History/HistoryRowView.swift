import SwiftUI

struct HistoryRowView: View {
    let model: HistoryRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow
            Text(model.summary)
                .font(.pcBody)
                .foregroundStyle(model.outcome == .failed ? Theme.error : Theme.text)
                .lineLimit(2)
            sinkRow
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            PCStatusDot(color: model.outcome == .success ? Theme.success : Theme.error)
            if let hash = model.shortHash {
                Text(hash)
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.text)
            }
            Text(model.dateLabel)
                .font(.pcMonoDetail)
                .foregroundStyle(Theme.dim)
            Spacer()
            Text(model.relativeTime)
                .font(.pcMonoDetail)
                .foregroundStyle(Theme.dim)
        }
    }

    private var sinkRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.sinkBadges.enumerated()), id: \.offset) { _, badge in
                HStack(spacing: 6) {
                    sinkIcon(for: badge)
                    PCPill(
                        text: badge.label,
                        monospaced: true,
                        foreground: badge.ok ? Theme.success : Theme.error,
                        background: Theme.elevated
                    )
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func sinkIcon(for badge: HistoryRowModel.SinkBadge) -> some View {
        let tint = badge.ok ? Theme.success : Theme.error
        switch badge.label.lowercased() {
        case "github":
            Image("github")
                .resizable()
                .renderingMode(.template)
                .frame(width: 14, height: 14)
                .foregroundStyle(tint)
        case "telegram":
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12))
                .foregroundStyle(tint)
        default:
            EmptyView()
        }
    }
}
