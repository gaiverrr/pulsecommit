import Foundation
import Observation
import SwiftUI
import HealthCore

@MainActor
@Observable
final class GitHubBranchPickerViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var branches: [String] = []
    var search: String = ""
    var state: LoadState = .idle

    let owner: String
    let repo: String
    private let loader: @Sendable (_ owner: String, _ repo: String) async throws -> [String]
    private let persist: @MainActor (String) -> Void
    private let onDismiss: @MainActor () -> Void
    private let onSessionExpired: @MainActor () -> Void

    init(
        owner: String,
        repo: String,
        loader: @escaping @Sendable (_ owner: String, _ repo: String) async throws -> [String],
        persist: @escaping @MainActor (String) -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) {
        self.owner = owner
        self.repo = repo
        self.loader = loader
        self.persist = persist
        self.onDismiss = onDismiss
        self.onSessionExpired = onSessionExpired
    }

    var filtered: [String] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return branches }
        return branches.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    func load() {
        state = .loading
        Task { [loader, owner, repo] in
            do {
                let result = try await loader(owner, repo)
                await MainActor.run {
                    self.branches = result
                    self.state = .loaded
                }
            } catch {
                let expired = Self.isSessionExpired(error)
                await MainActor.run {
                    self.state = .failed(gitHubUserFacingMessage(error))
                    if expired {
                        self.onSessionExpired()
                    }
                }
            }
        }
    }

    private static func isSessionExpired(_ error: Error) -> Bool {
        if let authError = error as? GitHubAuthError, authError == .sessionExpired {
            return true
        }
        if let fetchError = error as? GitHubBranchFetcherError, fetchError == .unauthorized {
            return true
        }
        return false
    }

    func select(_ branch: String) {
        persist(branch)
        onDismiss()
    }

    static func live(
        owner: String,
        repo: String,
        fetcher: GitHubBranchFetcher,
        token: @escaping @Sendable () async throws -> String,
        preferences: PreferencesStore,
        onDismiss: @escaping @MainActor () -> Void,
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) -> GitHubBranchPickerViewModel {
        GitHubBranchPickerViewModel(
            owner: owner,
            repo: repo,
            loader: { owner, repo in
                let t = try await token()
                return try await fetcher.loadBranches(owner: owner, repo: repo, token: t)
            },
            persist: { branch in preferences.githubBranch = branch },
            onDismiss: onDismiss,
            onSessionExpired: onSessionExpired
        )
    }
}

struct GitHubBranchPickerSheet: View {
    @Bindable var viewModel: GitHubBranchPickerViewModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("$ pulse branches")
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                searchField
                    .padding(.horizontal, 20)

                content
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Pick branch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { viewModel.load() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.dim)
            TextField("Search branches", text: $viewModel.search)
                .font(.pcMonoDetail)
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 32)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load branches")
                    .font(.pcBodySemibold)
                    .foregroundStyle(Theme.error)
                Text(message)
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.muted)
            }
            .padding(20)
        case .loaded:
            List(viewModel.filtered, id: \.self) { branch in
                Button {
                    viewModel.select(branch)
                } label: {
                    HStack {
                        Text(branch)
                            .font(.pcMonoDetail)
                            .foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
