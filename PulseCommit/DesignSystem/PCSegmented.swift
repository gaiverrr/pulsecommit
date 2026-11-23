import SwiftUI

struct PCSegmented<Option: Hashable & CustomStringConvertible>: View {
    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option.description)
                        .font(.pcBody)
                        .foregroundStyle(isSelected ? Color.black : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Theme.accent : Color.clear)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous).fill(Theme.elevated)
        )
    }
}
