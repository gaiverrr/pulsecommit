import SwiftUI

struct AutomaticWorkoutConsentSheet: View {
    let scope: AutomaticWorkoutConsentScope
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        let disclosure = AutomaticWorkoutDisclosure(scope: scope)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(disclosure.title)
                        .font(.pcLargeTitle)
                        .foregroundStyle(Theme.text)
                    disclosureRow("TARGET", disclosure.target)
                    disclosureRow("FIELDS", disclosure.fields)
                    disclosureRow("WHO MAY READ IT", disclosure.readers)
                    disclosureRow("RETENTION", disclosure.retention)
                    disclosureRow("TIMING", disclosure.timing)
                    disclosureRow("STOPPING", disclosure.revocation)
                    Text("This permission is separate from manual daily exports and applies only to this exact bot, chat, and topic.")
                        .font(.pcCaption)
                        .foregroundStyle(Theme.warn)
                    Button("Allow automatic workout messages", action: onAllow)
                        .buttonStyle(DSPrimaryButtonStyle())
                        .accessibilityIdentifier("automaticWorkout.consent.allow")
                    Button("Not now", action: onDecline)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 12)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Workout messages")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func disclosureRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.pcLabel).tracking(1.2).foregroundStyle(Theme.dim)
            Text(body).font(.pcBody).foregroundStyle(Theme.muted)
        }
    }
}
