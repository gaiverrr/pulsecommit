import Foundation

public enum GitHubSinkError: Error, Equatable, Sendable {
    case httpError(statusCode: Int, body: String?)
    case invalidResponse
    case decodingFailed
    case nonFastForwardExhausted(lastBody: String?)
}

extension GitHubSinkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpError(let status, let body):
            if let body, !body.isEmpty { return "GitHub HTTP \(status): \(body)" }
            return "GitHub HTTP \(status)"
        case .invalidResponse:
            return "GitHub returned a non-HTTP response"
        case .decodingFailed:
            return "GitHub response could not be decoded"
        case .nonFastForwardExhausted(let lastBody):
            if let lastBody, !lastBody.isEmpty {
                return "GitHub kept rejecting the commit after 4 attempts. Last response: \(lastBody)"
            }
            return "GitHub kept rejecting the commit after 4 attempts (422). Please retry."
        }
    }
}

public actor GitHubSink: GitRepoSink {
    public nonisolated let id: String
    public nonisolated var repositoryPath: String { credentialProvider.repositoryPath }
    public nonisolated var branch: String { credentialProvider.branch }

    private let credentialProvider: GitHubCredentialProvider
    private let session: URLSession
    private let decoder: JSONDecoder
    private let authorizePayload: @Sendable () async -> Bool

    // In-memory carry-forward of the SHA produced by the most recent successful
    // `updateRef`. The next `deliver` call uses this as the parent commit
    // instead of asking `getRef` again — `getRef` hits GitHub's edge cache and
    // can return a stale tip for many seconds after a write, which causes
    // multi-day exports to fail with 422 "Update is not a fast forward" even
    // after the 1s/3s/9s retry backoff. Cleared on 422 (some other writer
    // advanced the ref) and never persisted across process launches.
    private var lastPushedSha: String?

    public init(
        id: String = "github",
        credentialProvider: GitHubCredentialProvider,
        // No default: forces every call site to choose a session; production
        // must pass EphemeralAPISession so tokens never touch the shared URLCache.
        session: URLSession,
        authorizePayload: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.id = id
        self.credentialProvider = credentialProvider
        self.session = session
        self.decoder = JSONDecoder()
        self.authorizePayload = authorizePayload
    }

    // Initial attempt + up to 3 retries on 422 "Update is not a fast forward."
    // Each retry refreshes the ref from scratch and rebuilds the entire tree +
    // commit against the latest parent — never reuses state from a failed
    // attempt. Backoff grows exponentially (100ms, 300ms, 900ms) so the ref
    // has a chance to settle on GitHub's side between attempts. Previously the
    // sink retried only once; that's not enough when the branch tip moves
    // twice in quick succession (observed in the field after the Contents API
    // bootstrap commit warmed the ref cache, where the next two PATCH calls
    // both raced GitHub's eventual consistency).
    private static let maxNonFastForwardRetries = 3
    // Bumped from 100/300/900ms after a real-device test where 422 persisted
    // for ~24 seconds (longer than the original 1.3s total window). Eventual-
    // consistency on GitHub refs is sometimes that slow right after a
    // bootstrap commit. 1s/3s/9s totals 13s + HTTP latencies ≈ 18-20s worst
    // case, which is acceptable for a manually-triggered export.
    private static let nonFastForwardBackoffsNanos: [UInt64] = [
        1_000_000_000,
        3_000_000_000,
        9_000_000_000
    ]

    public func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        try await deliver(snapshot: snapshot, files: files, onAttempt: nil)
    }

    // Reentrancy invariant: `deliver` assumes a single concurrent caller per
    // GitHubSink instance. The Orchestrator guarantees this today — its outer
    // day loop is sequential and there is exactly one GitHubSink in the active
    // sinks array, so the actor's `lastPushedSha` cache is never read+written
    // by two in-flight `deliver` calls. If a future caller fans out per-day
    // sink calls in parallel on the same instance, the cache may be overwritten
    // between an `await` in `commitAndPush` and its `updateRef` write, producing
    // stale-parent 422s — the exact bug this cache is meant to prevent.
    public func deliver(
        snapshot: DailySnapshot,
        files: [FileEntry],
        onAttempt: AttemptHandler?
    ) async throws -> SinkResult {
        let token = try await credentialProvider.accessToken()
        let owner = credentialProvider.owner
        let repo = credentialProvider.repo
        let branch = credentialProvider.branch

        let prefixed = applySubdir(files)
        let message = makeMessage(for: snapshot)

        let totalAttempts = Self.maxNonFastForwardRetries + 1
        var lastBody: String?
        for attempt in 0...Self.maxNonFastForwardRetries {
            if attempt > 0 {
                await onAttempt?(attempt, totalAttempts, "non-fast-forward")
            }
            do {
                return try await commitAndPush(
                    owner: owner,
                    repo: repo,
                    branch: branch,
                    token: token,
                    files: prefixed,
                    message: message,
                    bootstrapIfEmpty: attempt == 0,
                    cachedParentSha: lastPushedSha
                )
            } catch let GitHubSinkError.httpError(statusCode: 422, body) {
                lastBody = body
                // Cached SHA is stale (or the ref moved under us). Drop it so
                // the next attempt — and any future deliver call on this sink —
                // round-trips through getRef to re-discover the real tip.
                lastPushedSha = nil
                if attempt == Self.maxNonFastForwardRetries {
                    throw GitHubSinkError.nonFastForwardExhausted(lastBody: lastBody)
                }
                try? await Task.sleep(nanoseconds: Self.nonFastForwardBackoffsNanos[attempt])
            }
        }
        throw GitHubSinkError.nonFastForwardExhausted(lastBody: lastBody)
    }

    // Single end-to-end commit cycle: getRef → getCommit → blobs → tree →
    // commit → PATCH. Throws GitHubSinkError.httpError(422, _) if the PATCH is
    // rejected as non-fast-forward; the caller decides whether to retry.
    // Bootstrap-via-Contents-API only runs on the very first attempt — once a
    // ref exists, an empty-repo signal would mean something else entirely.
    private func commitAndPush(
        owner: String,
        repo: String,
        branch: String,
        token: String,
        files: [FileEntry],
        message: String,
        bootstrapIfEmpty: Bool,
        cachedParentSha: String?
    ) async throws -> SinkResult {
        let parentSha: String
        if let cachedParentSha {
            // Trust the SHA we just wrote; skip getRef to avoid the stale-edge-
            // cache window that causes 422 on rapid back-to-back commits (the
            // 7-day backfill case).
            parentSha = cachedParentSha
        } else {
            let ref: GitHubRefResponse
            do {
                ref = try await getRef(owner: owner, repo: repo, branch: branch, token: token)
            } catch let GitHubSinkError.httpError(statusCode, body) where bootstrapIfEmpty && isEmptyRepository(statusCode: statusCode, body: body) {
                // Empty repo: the Git Data API (blobs/trees/commits) returns 409
                // "Git Repository is empty." until the repo has a first commit, so
                // we bootstrap via the Contents API (the only endpoint that can
                // create a commit on an empty repository), then continue with the
                // normal multi-file commit path. This produces TWO commits on the
                // very-first export (seed + daily snapshot) — accepted because the
                // alternative (one Contents API call per file) produces N commits.
                try await bootstrapEmptyRepository(
                    owner: owner, repo: repo, branch: branch, token: token, files: files
                )
                ref = try await getRef(owner: owner, repo: repo, branch: branch, token: token)
            }
            parentSha = ref.object.sha
        }
        let parent = try await getCommit(owner: owner, repo: repo, token: token, sha: parentSha)
        let commit = try await attemptCommit(
            owner: owner,
            repo: repo,
            token: token,
            parentSha: parentSha,
            baseTreeSha: parent.tree.sha,
            files: files,
            message: message
        )
        _ = try await updateRef(owner: owner, repo: repo, branch: branch, token: token, sha: commit.sha)
        lastPushedSha = commit.sha
        return .success(reference: commit.sha, url: commit.htmlURL.flatMap(URL.init(string:)))
    }

    private func attemptCommit(
        owner: String,
        repo: String,
        token: String,
        parentSha: String,
        baseTreeSha: String,
        files: [FileEntry],
        message: String
    ) async throws -> GitHubCommitResponse {
        // Blob creation is independent per file and dominated by RTT, so push
        // them through a bounded task group instead of awaiting one-at-a-time.
        // A typical daily snapshot has ~13 files (summary.json/md + samples/* +
        // workouts/* + routes/*) and per-blob RTT is ~150ms on LTE, so a serial
        // loop costs ~2s just for blobs. Concurrency 4 brings that closer to
        // ~500ms while staying far below GitHub's 5000 req/h rate-limit ceiling.
        let blobShas = try await uploadBlobsConcurrently(
            owner: owner,
            repo: repo,
            token: token,
            files: files,
            maxConcurrency: 4
        )
        let entries = zip(files, blobShas).map { GitHubTreeEntry(path: $0.0.path, sha: $0.1) }
        let tree = try await createTree(owner: owner, repo: repo, token: token, baseTree: baseTreeSha, entries: entries)
        return try await createCommit(owner: owner, repo: repo, token: token, message: message, tree: tree.sha, parents: [parentSha])
    }

    private func uploadBlobsConcurrently(
        owner: String,
        repo: String,
        token: String,
        files: [FileEntry],
        maxConcurrency: Int
    ) async throws -> [String] {
        guard !files.isEmpty else { return [] }
        let cap = max(1, min(maxConcurrency, files.count))
        var shas = [String?](repeating: nil, count: files.count)
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var nextIndex = 0
            while nextIndex < cap {
                let i = nextIndex
                let data = files[i].data
                group.addTask {
                    let blob = try await self.createBlob(owner: owner, repo: repo, token: token, content: data)
                    return (i, blob.sha)
                }
                nextIndex += 1
            }
            while let (i, sha) = try await group.next() {
                shas[i] = sha
                if nextIndex < files.count {
                    let j = nextIndex
                    let data = files[j].data
                    group.addTask {
                        let blob = try await self.createBlob(owner: owner, repo: repo, token: token, content: data)
                        return (j, blob.sha)
                    }
                    nextIndex += 1
                }
            }
        }
        return shas.compactMap { $0 }
    }

    // Bootstrap a brand-new empty repository via the Contents API. This is the
    // only GitHub endpoint that can create the first commit on an empty repo;
    // the Git Data API rejects every blob/tree/commit call with 409
    // "Git Repository is empty." until at least one commit exists.
    // https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents
    private func bootstrapEmptyRepository(
        owner: String,
        repo: String,
        branch: String,
        token: String,
        files: [FileEntry]
    ) async throws {
        // Prefer summary.md as the seed file because it is small (~1 KB) and
        // human-readable on the repo landing page. Fall back to the first file
        // if no summary.md is present in this snapshot.
        let seed = files.first(where: { $0.path.hasSuffix("summary.md") }) ?? files.first
        guard let seed else { return }
        let request = try GitHubAPI.createContentsRequest(
            owner: owner,
            repo: repo,
            token: token,
            branch: branch,
            path: seed.path,
            contentBase64: seed.data.base64EncodedString(),
            message: "Pulse Commit · initial commit"
        )
        _ = try await send(request, expecting: GitHubCreateContentsResponse.self)
    }

    private func isEmptyRepository(statusCode: Int, body: String?) -> Bool {
        if statusCode == 404 { return true }
        if statusCode == 409, let body, body.contains("Git Repository is empty") { return true }
        return false
    }

    private func applySubdir(_ files: [FileEntry]) -> [FileEntry] {
        let subdir = credentialProvider.subdir
        guard !subdir.isEmpty else { return files }
        let trimmed = subdir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return files }
        return files.map { FileEntry(path: "\(trimmed)/\($0.path)", data: $0.data) }
    }

    private func makeMessage(for snapshot: DailySnapshot) -> String {
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        var parts: [String] = []
        if let steps = stepsTotal(snapshot) {
            parts.append("\(steps) steps")
        }
        let count = snapshot.workouts.count
        parts.append("\(count) workout\(count == 1 ? "" : "s")")
        if let sleep = sleepMinutes(snapshot) {
            let h = sleep / 60
            let m = sleep % 60
            parts.append("sleep \(h)h\(String(format: "%02d", m))m")
        }
        let suffix = parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
        return "chore: pulse \(dayKey)\(suffix)"
    }

    private func stepsTotal(_ snapshot: DailySnapshot) -> Int? {
        guard let m = snapshot.summaries["steps"]?.metrics["total"] else { return nil }
        switch m {
        case .int(let i): return i
        case .double(let d): return Int(d.rounded())
        case .string: return nil
        }
    }

    private func sleepMinutes(_ snapshot: DailySnapshot) -> Int? {
        guard let m = snapshot.summaries["sleep"]?.metrics["duration_minutes"] else { return nil }
        switch m {
        case .int(let i): return i
        case .double(let d): return Int(d.rounded())
        case .string: return nil
        }
    }

    // MARK: - HTTP

    private func getRef(owner: String, repo: String, branch: String, token: String) async throws -> GitHubRefResponse {
        let request = GitHubAPI.getRefRequest(owner: owner, repo: repo, branch: branch, token: token)
        return try await send(request, expecting: GitHubRefResponse.self)
    }

    private func getCommit(owner: String, repo: String, token: String, sha: String) async throws -> GitHubGetCommitResponse {
        let request = GitHubAPI.getCommitRequest(owner: owner, repo: repo, token: token, sha: sha)
        return try await send(request, expecting: GitHubGetCommitResponse.self)
    }

    private func createBlob(owner: String, repo: String, token: String, content: Data) async throws -> GitHubBlobResponse {
        let request = try GitHubAPI.createBlobRequest(owner: owner, repo: repo, token: token, content: content)
        return try await send(request, expecting: GitHubBlobResponse.self)
    }

    private func createTree(owner: String, repo: String, token: String, baseTree: String?, entries: [GitHubTreeEntry]) async throws -> GitHubTreeResponse {
        let request = try GitHubAPI.createTreeRequest(owner: owner, repo: repo, token: token, baseTree: baseTree, entries: entries)
        return try await send(request, expecting: GitHubTreeResponse.self)
    }

    private func createCommit(owner: String, repo: String, token: String, message: String, tree: String, parents: [String]) async throws -> GitHubCommitResponse {
        let request = try GitHubAPI.createCommitRequest(owner: owner, repo: repo, token: token, message: message, tree: tree, parents: parents)
        return try await send(request, expecting: GitHubCommitResponse.self)
    }

    private func updateRef(owner: String, repo: String, branch: String, token: String, sha: String) async throws -> GitHubRefResponse {
        let request = try GitHubAPI.updateRefRequest(owner: owner, repo: repo, branch: branch, token: token, sha: sha)
        return try await send(request, expecting: GitHubRefResponse.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, expecting: T.Type) async throws -> T {
        if request.httpMethod != "GET" {
            guard await authorizePayload() else { throw HealthExportAuthorizationError.consentRequired }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubSinkError.invalidResponse
        }
        if http.statusCode == 401 {
            await credentialProvider.invalidateSession()
            throw GitHubAuthError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw GitHubSinkError.httpError(statusCode: http.statusCode, body: body)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubSinkError.decodingFailed
        }
    }
}
