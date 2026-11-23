import SwiftUI

struct HealthRationaleView: View {
    let onContinue: () -> Void

    static var categories: [String] {
        if #available(iOS 18.0, *) {
            return categories(stateOfMindAvailable: true)
        } else {
            return categories(stateOfMindAvailable: false)
        }
    }

    static func categories(stateOfMindAvailable: Bool) -> [String] {
        var names: [String] = [
            "Steps",
            "Distance",
            "Active Energy",
            "Activity Rings",
            "Heart Rate",
            "Resting HR",
            "HRV",
            "VO₂ Max",
            "Sleep",
            "Sleep Respiratory Rate",
            "Wrist Temperature",
            "Body Mass"
        ]
        if stateOfMindAvailable {
            names.append("State of Mind")
        }
        names.append("Workouts")
        names.append("Workout Routes")
        names.append("Nutrition")
        return names
    }

    static let tipLine: String = "> tip: data stays on device until you configure a destination"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("$ which categories?")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)

                    Text("Which Health\ncategories?")
                        .font(.pcLargeTitle)
                        .foregroundStyle(Theme.text)

                    Text("These are the HealthKit types Pulse Commit will read. You can adjust them in the Categories tab later.")
                        .font(.pcBodyLarge)
                        .foregroundStyle(Theme.muted)

                    PCCodeBlock(content: codeBlockContent)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(HealthRationaleView.tipLine)
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.accent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onContinue) {
                Text("Continue")
            }
            .buttonStyle(DSPrimaryButtonStyle(glows: true))
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var codeBlockContent: String {
        var lines: [String] = ["read:"]
        for (idx, name) in HealthRationaleView.categories.enumerated() {
            let prefix = idx == HealthRationaleView.categories.count - 1 ? "└──" : "├──"
            lines.append("\(prefix) \(name)")
        }
        return lines.joined(separator: "\n")
    }
}
