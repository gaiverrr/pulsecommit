import SwiftUI
import UIKit

struct HistoryDetailView: View {
    let entry: HistoryEntrySnapshot
    @State private var copyFeedback: String?

    init(entry: HistoryEntrySnapshot) {
        self.entry = entry
    }

    /// Convenience for tests that build a live `HistoryEntry` inline. UI code
    /// must always pass a `HistoryEntrySnapshot` to avoid the orphan-context
    /// SwiftData footgun.
    init(entry: HistoryEntry) {
        self.entry = HistoryEntrySnapshot(entry: entry)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusPill
                metadataCard
                if entry.status == .success {
                    successCard
                } else {
                    errorCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.text)
    }

    var shortHash: String {
        if let sha = entry.githubCommitSha, !sha.isEmpty {
            return String(sha.prefix(8))
        }
        return String(entry.id.uuidString.prefix(8)).lowercased()
    }

    var fullErrorMessage: String {
        entry.displayErrorMessage ?? "export failed"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ pulse log show \(shortHash)")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
            Text(entry.status == .success ? "Commit detail" : "Failure detail")
                .font(.pcTitle)
                .foregroundStyle(Theme.text)
        }
    }

    private var statusPill: some View {
        HStack {
            PCPill(
                text: entry.status == .success ? "● SUCCESS" : "● FAILED",
                monospaced: true,
                foreground: entry.status == .success ? Theme.success : Theme.error,
                background: Theme.elevated
            )
            Spacer()
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PCSectionHeader(title: "METADATA")
            PCCard {
                VStack(alignment: .leading, spacing: 10) {
                    metaRow(label: "started", value: Self.format(entry.startedAt))
                    metaRow(label: "finished", value: Self.format(entry.finishedAt))
                    metaRow(label: "sinks", value: entry.sinks.isEmpty ? "—" : entry.sinks.joined(separator: ", "))
                    metaRow(label: "days", value: "\(entry.daysCovered.count)")
                }
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .font(.pcLabel)
                .tracking(1.5)
                .foregroundStyle(Theme.dim)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.pcMonoDetail)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var errorCard: some View {
        // The outer view is a ScrollView; nesting another vertical ScrollView
        // here causes touch conflicts on iOS where the inner area becomes
        // unscrollable. Let PCCodeBlock expand naturally and the outer scroll
        // handles long Telegram error payloads.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                PCSectionHeader(title: "ERROR")
                Spacer()
                Button {
                    UIPasteboard.general.string = fullErrorMessage
                    copyFeedback = "Copied"
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copyFeedback = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copyFeedback ?? "Copy")
                            .font(.pcCaptionMono)
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy error to clipboard")
            }
            PCCodeBlock(content: fullErrorMessage)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var successCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PCSectionHeader(title: "ARTIFACTS")
            PCCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let urlString = entry.githubCommitURLString, let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack {
                                Image("github")
                                    .resizable()
                                    .renderingMode(.template)
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(Theme.accent)
                                Text("github commit")
                                    .font(.pcBody)
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(String((entry.githubCommitSha ?? "").prefix(8)))
                                    .font(.pcMonoDetail)
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    if let tg = entry.telegramMessageReference {
                        HStack {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(Theme.accent)
                            Text("telegram message")
                                .font(.pcBody)
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(tg)
                                .font(.pcMonoDetail)
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if entry.githubCommitURLString == nil && entry.telegramMessageReference == nil {
                        Text("> no external references recorded")
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    private static func format(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: date)
    }
}
