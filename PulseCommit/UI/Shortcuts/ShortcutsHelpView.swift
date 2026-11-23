import SwiftUI
import UIKit

struct ShortcutsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                lockedPhoneNote
                PCSectionHeader(title: "Recipes", hint: "PERSONAL AUTOMATION")
                VStack(spacing: 14) {
                    recipeCard(
                        title: "Evening Today",
                        tag: "LIVE",
                        description: Text("Exports the current local day from ")
                            + Text("00:00").font(.pcCaptionMono)
                            + Text(" to the time the action runs."),
                        snippet: "$ 21:00 daily → Export Health Data · Today"
                    )
                    recipeCard(
                        title: "Morning Yesterday",
                        tag: "COMPLETE",
                        description: Text("Exports the completed local calendar day before the action runs."),
                        snippet: "$ 08:30 daily → Export Last Day"
                    )
                }
                PCSectionHeader(title: "App Intents", hint: "OPEN IN SHORTCUTS")
                VStack(spacing: 14) {
                    intentCard(
                        title: "Export Last Day",
                        tag: "CRON",
                        description: Text("Yesterday · enabled categories · configured destinations"),
                        snippet: "$ pulse-commit export-last-day"
                    )
                    intentCard(
                        title: "Export Health Data",
                        tag: "FLEX",
                        description: Text("Today / ")
                            + Text("1d / 7d / 30d").font(.pcCaptionMono)
                            + Text(" · enabled categories · destination picker"),
                        snippet: "$ pulse-commit export --window=today"
                    )
                    intentCard(
                        title: "Backfill Range",
                        tag: "RANGE",
                        description: Text("Date range · enabled categories · configured destinations"),
                        snippet: "$ pulse-commit backfill --from=…"
                    )
                }
                footer
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Automate")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        Text("Build a Time of Day automation in Apple's Shortcuts app. Pulse Commit provides the actions; iOS runs the schedule.")
            .font(.pcCaptionMono)
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockedPhoneNote: some View {
        PCCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locked iPhone")
                        .font(.pcBodySemibold)
                        .foregroundStyle(Theme.text)
                    Text("When iPhone is locked, automation may not run or finish. Unlock, open Pulse Commit, and retry.")
                        .font(.pcCaption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func recipeCard(
        title: String,
        tag: String,
        description: Text,
        snippet: String
    ) -> some View {
        PCCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.pcBodySemibold)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    PCPill(text: tag, foreground: Theme.muted, background: Theme.elevated)
                }
                description
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
                PCCodeBlock(content: snippet, padding: 10, cornerRadius: 8)
            }
        }
    }

    private func intentCard(
        title: String,
        tag: String,
        description: Text,
        snippet: String
    ) -> some View {
        PCCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.pcBodySemibold)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    PCPill(text: tag, foreground: Theme.muted, background: Theme.elevated)
                }
                description
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
                PCCodeBlock(content: snippet, padding: 10, cornerRadius: 8)
                Button {
                    if let url = URL(string: "shortcuts://"), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Open Shortcuts")
                            .font(.pcBodySemibold)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("> Today is still in progress.")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.faint)
            Text("> Generated/Latest sample are timestamps, not proof Apple Watch sync is complete.")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.faint)
        }
        .padding(.top, 4)
    }
}
