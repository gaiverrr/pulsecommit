import Foundation

public struct GitHubRefObject: Codable, Equatable, Sendable {
    public let sha: String
    public let type: String
    public let url: String
}

public struct GitHubRefResponse: Codable, Equatable, Sendable {
    public let ref: String
    public let object: GitHubRefObject
}

public struct GitHubCreateBlobRequest: Codable, Equatable, Sendable {
    public let content: String
    public let encoding: String

    public init(content: String, encoding: String = "base64") {
        self.content = content
        self.encoding = encoding
    }
}

public struct GitHubBlobResponse: Codable, Equatable, Sendable {
    public let sha: String
    public let url: String
}

public struct GitHubGetCommitTree: Codable, Equatable, Sendable {
    public let sha: String
    public let url: String
}

public struct GitHubGetCommitResponse: Codable, Equatable, Sendable {
    public let sha: String
    public let tree: GitHubGetCommitTree
}

public struct GitHubTreeEntry: Codable, Equatable, Sendable {
    public let path: String
    public let mode: String
    public let type: String
    public let sha: String

    public init(path: String, sha: String, mode: String = "100644", type: String = "blob") {
        self.path = path
        self.mode = mode
        self.type = type
        self.sha = sha
    }
}

public struct GitHubCreateTreeRequest: Codable, Equatable, Sendable {
    public let baseTree: String?
    public let tree: [GitHubTreeEntry]

    enum CodingKeys: String, CodingKey {
        case baseTree = "base_tree"
        case tree
    }

    public init(baseTree: String?, tree: [GitHubTreeEntry]) {
        self.baseTree = baseTree
        self.tree = tree
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let baseTree {
            try container.encode(baseTree, forKey: .baseTree)
        }
        try container.encode(tree, forKey: .tree)
    }
}

public struct GitHubTreeResponse: Codable, Equatable, Sendable {
    public let sha: String
    public let url: String
}

public struct GitHubCreateCommitRequest: Codable, Equatable, Sendable {
    public let message: String
    public let tree: String
    public let parents: [String]

    public init(message: String, tree: String, parents: [String]) {
        self.message = message
        self.tree = tree
        self.parents = parents
    }
}

public struct GitHubCommitResponse: Codable, Equatable, Sendable {
    public let sha: String
    public let url: String
    public let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case sha
        case url
        case htmlURL = "html_url"
    }
}

public struct GitHubCreateRefRequest: Codable, Equatable, Sendable {
    public let ref: String
    public let sha: String

    public init(ref: String, sha: String) {
        self.ref = ref
        self.sha = sha
    }
}

// https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents
public struct GitHubCreateContentsRequest: Codable, Equatable, Sendable {
    public let message: String
    public let content: String
    public let branch: String

    public init(message: String, content: String, branch: String) {
        self.message = message
        self.content = content
        self.branch = branch
    }
}

public struct GitHubCreateContentsCommit: Codable, Equatable, Sendable {
    public let sha: String
    public let url: String?
    public let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case sha
        case url
        case htmlURL = "html_url"
    }
}

public struct GitHubCreateContentsResponse: Codable, Equatable, Sendable {
    public let commit: GitHubCreateContentsCommit
}

public struct GitHubUpdateRefRequest: Codable, Equatable, Sendable {
    public let sha: String
    public let force: Bool

    public init(sha: String, force: Bool = false) {
        self.sha = sha
        self.force = force
    }
}
