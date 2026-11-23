import SwiftUI

struct DSPrimaryButtonStyle: ButtonStyle {
    var glows: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pcBodyLarge.weight(.semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent)
            )
            .shadow(
                color: glows ? Theme.accent.opacity(0.35) : .clear,
                radius: glows ? 24 : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
