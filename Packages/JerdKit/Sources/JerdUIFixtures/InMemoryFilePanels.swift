import Foundation
import JerdUI

/// Answers open panels from a queue of prepared results, and records each request.
@MainActor
public final class InMemoryFilePanels: FilePanelPresenting {
    /// The answers, in order. A missing answer means the user cancelled.
    public var answers: [URL?]
    public private(set) var requests: [FilePanelRequest] = []

    public init(answers: [URL?] = []) {
        self.answers = answers
    }

    public func choose(_ request: FilePanelRequest) async -> URL? {
        requests.append(request)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}
