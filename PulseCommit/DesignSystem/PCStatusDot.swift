import SwiftUI

struct PCStatusDot: View {
    var color: Color = Theme.success
    var pulsing: Bool = false
    var diameter: CGFloat = 8

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .opacity(pulseOpacity)
            .onAppear { startIfNeeded() }
            .onChange(of: pulsing) { _, _ in startIfNeeded() }
    }

    private func startIfNeeded() {
        if pulsing {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.4
            }
        } else {
            pulseOpacity = 1.0
        }
    }
}
