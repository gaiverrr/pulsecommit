import SwiftUI

struct PCPill: View {
    let text: String
    var monospaced: Bool = false
    var foreground: Color = Theme.muted
    var background: Color = Theme.elevated
    var borderColor: Color? = nil

    var body: some View {
        Text(text)
            .font(monospaced ? .pcCaptionMono : .pcLabel)
            .tracking(monospaced ? 0 : 1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous).fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor ?? .clear, lineWidth: borderColor == nil ? 0 : 1)
            )
    }
}
