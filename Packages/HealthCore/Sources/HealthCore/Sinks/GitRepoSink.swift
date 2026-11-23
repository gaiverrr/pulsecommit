import Foundation

public protocol GitRepoSink: Sink {
    var repositoryPath: String { get }
    var branch: String { get }
}
