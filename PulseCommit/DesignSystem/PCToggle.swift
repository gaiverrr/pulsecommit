import SwiftUI

struct PCToggle: View {
    let title: String
    let accessibilityLabel: String?
    @Binding var isOn: Bool

    init(title: String = "", accessibilityLabel: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self._isOn = isOn
    }

    var body: some View {
        Group {
            if title.isEmpty {
                // A hidden-label Toggle reads as a bare "switch" to
                // VoiceOver; call sites must say what it switches.
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .accessibilityLabel(accessibilityLabel ?? "")
            } else {
                Toggle(title, isOn: $isOn)
            }
        }
        .tint(Theme.accent)
    }
}
