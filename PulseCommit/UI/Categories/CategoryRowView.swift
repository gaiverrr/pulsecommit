import SwiftUI

struct CategoryRowView: View {
    let spec: CategoryRowSpec
    let isOn: Bool
    let isLocked: Bool
    let liveValue: String?
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            iconChip
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.displayName)
                    .font(.pcBody)
                    .foregroundStyle(isOn ? Theme.text : Theme.muted)
                if let liveValue {
                    Text(liveValue)
                        .font(.pcMonoDetail)
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onToggle($0) }))
                .labelsHidden()
                .tint(Theme.accent)
                .disabled(isLocked)
                .accessibilityLabel(spec.displayName)
        }
        .padding(.vertical, 8)
    }

    private var iconChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? Theme.accentSoft : Theme.elevated)
                .frame(width: 32, height: 32)
            Image(systemName: spec.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isOn ? Theme.accent : Theme.dim)
        }
    }
}
