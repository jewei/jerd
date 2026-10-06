import Foundation

@testable import JerdSystem

/// A copy of the old `JerdCore.JerdHelperProtocol` declaration, under another runtime name.
/// XPC matches selectors and types, not protocol names, so this stands for an installed old helper.
@objc(LegacyJerdHelperProtocol) protocol LegacyJerdHelperProtocol {
    func status(reply: @escaping @Sendable (Data?, String?) -> Void)
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void)
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void)
    func releaseListeners(reply: @escaping @Sendable () -> Void)
    func removeSetup(reply: @escaping @Sendable (String?) -> Void)
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void)
}
