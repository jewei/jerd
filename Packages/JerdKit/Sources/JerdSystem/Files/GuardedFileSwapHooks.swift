/// Test seams of `GuardedFileSwap`. Each hook can simulate a racing writer or fail on purpose.
package struct GuardedFileSwapHooks: Sendable {
    package var preExchange: (@Sendable () throws -> Void)?
    package var preRestore: (@Sendable () throws -> Void)?

    package init(preExchange: (@Sendable () throws -> Void)? = nil, preRestore: (@Sendable () throws -> Void)? = nil) {
        self.preExchange = preExchange
        self.preRestore = preRestore
    }

    func beforeExchange() throws { try preExchange?() }
    func beforeUndo() throws { try preRestore?() }
}
