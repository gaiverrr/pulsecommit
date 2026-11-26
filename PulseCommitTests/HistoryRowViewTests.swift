import SwiftUI
import UIKit
import XCTest
@testable import PulseCommit

@MainActor
final class HistoryRowBadgeLayoutTests: XCTestCase {
    private let webhookLabel = "agent.example.net · HTTP 200"
    private let spacing: CGFloat = 6

    private func row(_ badges: [HistoryRowModel.SinkBadge]) -> HistoryRowModel {
        HistoryRowModel(
            id: UUID(),
            outcome: .success,
            shortHash: "a4f03a9c",
            dateLabel: "2026-11-26",
            relativeTime: "Today · 21:00",
            summary: "exported 1 day",
            sinkBadges: badges
        )
    }

    private func height<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func test_longWebhookBadge_movesToItsOwnLineInsteadOfWrapping() {
        let base = [
            HistoryRowModel.SinkBadge(label: "github", ok: true, kind: "github"),
            HistoryRowModel.SinkBadge(label: "telegram", ok: true, kind: "telegram")
        ]
        let webhook = HistoryRowModel.SinkBadge(label: webhookLabel, ok: true, kind: "webhook")
        let narrow: CGFloat = 370
        let twoBadges = height(HistoryRowView(model: row(base)), width: narrow)
        let pill = height(PCPill(text: webhookLabel, monospaced: true), width: 2000)
        let threeBadges = height(HistoryRowView(model: row(base + [webhook])), width: narrow)
        XCTAssertEqual(threeBadges, twoBadges + pill + spacing, accuracy: 1)
        let wide = height(HistoryRowView(model: row(base + [webhook])), width: 2000)
        XCTAssertEqual(wide, twoBadges, accuracy: 1)
    }

    private var longHostBadges: [HistoryRowModel.SinkBadge] {
        let host = String(repeating: "a", count: 48) + ".example.net"
        XCTAssertEqual(host.count, 60)
        return [
            HistoryRowModel.SinkBadge(label: "github", ok: true, kind: "github"),
            HistoryRowModel.SinkBadge(label: "telegram", ok: true, kind: "telegram"),
            HistoryRowModel.SinkBadge(label: "\(host) · HTTP 200", ok: true, kind: "webhook")
        ]
    }

    private func size<V: View>(_ view: V, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func test_sixtyCharacterHost_staysWithinRowWidth() {
        let narrow: CGFloat = 370
        let regular = size(HistoryRowView(model: row(longHostBadges)), width: narrow)
        XCTAssertLessThanOrEqual(regular.width, narrow)
        let accessibility = size(
            HistoryRowView(model: row(longHostBadges)).environment(\.dynamicTypeSize, .accessibility3),
            width: narrow
        )
        XCTAssertLessThanOrEqual(accessibility.width, narrow)
    }

    func test_singleBadge_hasNoEmptyLine() {
        let narrow: CGFloat = 370
        let short = height(HistoryRowView(model: row([
            HistoryRowModel.SinkBadge(label: "github", ok: true, kind: "github")
        ])), width: narrow)
        let longOnly = size(HistoryRowView(model: row(Array(longHostBadges.suffix(1)))), width: narrow)
        XCTAssertEqual(longOnly.height, short, accuracy: 0.5)
        XCTAssertLessThanOrEqual(longOnly.width, narrow)
    }
}

@MainActor
final class HistoryRowViewTests: XCTestCase {
    private func makeRow(outcome: HistoryRowModel.Outcome, id: UUID = UUID()) -> HistoryRowModel {
        HistoryRowModel(
            id: id,
            outcome: outcome,
            shortHash: "abc12345",
            dateLabel: "2026-05-10",
            relativeTime: "Today · 14:30",
            summary: "—",
            sinkBadges: []
        )
    }

    func test_rowsAreTappable_whenEntryProviderReturnsEntry() {
        let id = UUID()
        let row = makeRow(outcome: .failed, id: id)
        let snapshot = HistoryEntrySnapshot(
            id: id,
            startedAt: Date(),
            finishedAt: Date(),
            status: .failed,
            sinks: [],
            daysCovered: [],
            errorMessage: "Telegram 400"
        )
        let view = HistoryView(
            rows: [row],
            totalCommits: 1,
            totalFailures: 1,
            sinceLabel: "May 2026",
            entryProvider: { lookupId in lookupId == id ? snapshot : nil }
        )
        XCTAssertTrue(view.rowIsTappable(row))
    }

    func test_rowsNotTappable_withoutEntryProvider() {
        let row = makeRow(outcome: .failed)
        let view = HistoryView(
            rows: [row],
            totalCommits: 1,
            totalFailures: 1,
            sinceLabel: "May 2026"
        )
        XCTAssertFalse(view.rowIsTappable(row))
    }
}
