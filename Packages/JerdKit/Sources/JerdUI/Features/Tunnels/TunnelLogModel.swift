import Foundation
import Observation

/// The connector log sheet of one tunnel. It loads on open and on Refresh.
@MainActor
@Observable
public final class TunnelLogModel: Identifiable {
    public let id: UUID
    public let name: String
    public internal(set) var text = ""
    public internal(set) var isLoading = false
    public internal(set) var failure: String?
    @ObservationIgnored private let port: any TunnelsPort

    public init(id: UUID, name: String, port: any TunnelsPort) {
        self.id = id
        self.name = name
        self.port = port
    }

    public var title: String { "\(name) Log" }

    /// Reads the recent connector events again.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            text = try await port.log(id: id)
            failure = nil
        } catch {
            failure = ErrorText.message(for: error)
        }
    }
}
