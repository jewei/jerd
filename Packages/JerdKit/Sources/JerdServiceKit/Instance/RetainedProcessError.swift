import Foundation

/// A start step stopped its process and the stop timed out. The process stays owned, so the
/// start failure path does not wait a second time.
struct RetainedProcessError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
