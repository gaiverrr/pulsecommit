import SwiftUI

struct PrivacyView: View {
    static let policyURLString = "https://pulsecommit.app/privacy"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                PCCard {
                    VStack(alignment: .leading, spacing: 14) {
                        privacyParagraph(
                            title: "We collect nothing.",
                            body: "Pulse Commit has no server of its own, no analytics, no telemetry. It connects only to api.github.com, github.com (sign-in), api.telegram.org, and the HTTPS webhook URL you enter. We do not see your Health data, your tokens, or even know that you installed the app."
                        )
                        Divider().background(Theme.divider)
                        privacyParagraph(
                            title: "Where your data goes.",
                            body: "Before the first export to each exact GitHub repo, Telegram chat/topic or webhook URL, Pulse Commit shows the selected Health categories, formats, possible readers, and remote retention. You must allow each destination separately. GitHub data may be visible to collaborators, organization readers, or anyone if the repo is public. Telegram data may be available to chat members and bot operators; an AI service may process it only when you chose an AI-backed bot or chat. The owner of your webhook URL receives the summary and file list, can keep them, and may pass them to an AI service. Pulse Commit has no AI integration."
                        )
                        Divider().background(Theme.divider)
                        privacyParagraph(
                            title: "Automatic workouts are a separate opt-in.",
                            body: "When enabled, Pulse Commit checks up to the last 72 hours after your opt-in and sends one text-only Telegram message per saved workout to the exact chat/topic you approved. No routes, GPS, raw heart-rate samples, custom zones, daily totals, ZIP, or JSON are included. Local delivery metadata prevents automatic duplicates; an uncertain result requires a warned manual retry."
                        )
                        Divider().background(Theme.divider)
                        privacyParagraph(
                            title: "Tokens stay on device.",
                            body: "GitHub OAuth tokens, Telegram bot tokens and webhook tokens live in the iOS Keychain. They are never logged and never sent to us. Each token goes only to its own service: GitHub, Telegram or your webhook URL. The Copy button on the Webhook screen puts the webhook token on this iPhone's clipboard for 2 minutes, only when you tap it."
                        )
                        Divider().background(Theme.divider)
                        privacyParagraph(
                            title: "Reset is in your hands.",
                            body: "Changing a destination or selected categories requires consent again. Disabling a destination or Settings → Reset all data clears its local consent along with local state. It does not delete commits in GitHub or messages in Telegram or data at your webhook; remove those copies with the destination and, for bots and webhooks, its operator."
                        )
                    }
                }
                Text("> 0 servers · 0 trackers · 0 cookies")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 4)
                Link(destination: URL(string: PrivacyView.policyURLString)!) {
                    Text("Read the full Privacy Policy")
                        .font(.pcBodySemibold)
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ cat PRIVACY.md")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func privacyParagraph(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.pcBodySemibold)
                .foregroundStyle(Theme.text)
            Text(body)
                .font(.pcCaption)
                .foregroundStyle(Theme.muted)
        }
    }
}
