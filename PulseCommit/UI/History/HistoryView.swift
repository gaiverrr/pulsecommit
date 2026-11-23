import SwiftUI

enum HistoryFilter: String, CaseIterable, Hashable, CustomStringConvertible {
    case all
    case success
    case failed

    var description: String {
        switch self {
        case .all: return "All"
        case .success: return "Success"
        case .failed: return "Failed"
        }
    }

    func matches(_ row: HistoryRowModel) -> Bool {
        switch self {
        case .all: return true
        case .success: return row.outcome == .success
        case .failed: return row.outcome == .failed
        }
    }
}

struct HistoryView: View {
    let rows: [HistoryRowModel]
    let totalCommits: Int
    let totalFailures: Int
    let sinceLabel: String
    var entryProvider: (UUID) -> HistoryEntrySnapshot? = { _ in nil }
    @State private var filter: HistoryFilter = .all

    var filteredRows: [HistoryRowModel] {
        rows.filter { filter.matches($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                PCSegmented(options: HistoryFilter.allCases, selection: $filter)
                listCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("History")
                        .font(.pcLargeTitle)
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                PCPill(
                    text: "$ git log --oneline",
                    monospaced: true,
                    foreground: Theme.muted,
                    background: Theme.elevated
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        "\(totalCommits) commits · \(totalFailures) failures · since \(sinceLabel)"
    }

    func rowIsTappable(_ row: HistoryRowModel) -> Bool {
        entryProvider(row.id) != nil
    }

    @ViewBuilder
    private func rowView(_ row: HistoryRowModel) -> some View {
        if let entry = entryProvider(row.id) {
            NavigationLink(value: HistoryNavigation.detail(entry.id)) {
                HistoryRowView(model: row)
            }
            .buttonStyle(.plain)
        } else {
            HistoryRowView(model: row)
        }
    }

    @ViewBuilder
    private var listCard: some View {
        if filteredRows.isEmpty {
            PCCard {
                Text("> no entries match this filter")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        } else {
            PCCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                        rowView(row)
                        if index < filteredRows.count - 1 {
                            Divider().overlay(Theme.divider)
                        }
                    }
                }
            }
        }
    }
}

enum HistoryNavigation: Hashable {
    case detail(UUID)
}

struct HistoryContainerView: View {
    @EnvironmentObject var container: AppContainer
    @State private var rows: [HistoryRowModel] = []
    @State private var entries: [HistoryEntrySnapshot] = []
    @State private var totalCommits: Int = 0
    @State private var totalFailures: Int = 0
    @State private var sinceLabel: String = "—"
    @State private var path: [HistoryNavigation] = []

    var body: some View {
        NavigationStack(path: $path) {
            HistoryView(
                rows: rows,
                totalCommits: totalCommits,
                totalFailures: totalFailures,
                sinceLabel: sinceLabel,
                entryProvider: { id in entries.first { $0.id == id } }
            )
            .navigationDestination(for: HistoryNavigation.self) { destination in
                switch destination {
                case .detail(let id):
                    if let snapshot = entries.first(where: { $0.id == id }) {
                        HistoryDetailView(entry: snapshot)
                    } else {
                        Text("Entry not found")
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        let loaded = (try? container.history.recentEntries(limit: 50)) ?? []
        let now = Date()
        entries = loaded
        rows = loaded.map { HistoryRowModel.from(snapshot: $0, now: now) }
        totalCommits = loaded.count
        totalFailures = loaded.filter { $0.status != HistoryEntry.Status.success }.count
        if let earliest = loaded.last?.startedAt {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "MMM yyyy"
            sinceLabel = df.string(from: earliest)
        } else {
            sinceLabel = "—"
        }
    }
}
