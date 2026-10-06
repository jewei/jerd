import JerdFoundation

/// The manager messages of a single-instance service. Each service words them for its own page.
package struct SingleServiceMessages: Sendable {
    /// Another operation is in progress.
    package var busy: String
    /// An operation ran before `load()`.
    package var notLoaded: JerdError
    /// An operation other than load, start, or stop ran while a runtime update needs recovery.
    package var updatePending: JerdError
    /// No runtime is registered.
    package var runtimeMissing: JerdError
    /// `registerRuntime` named another runtime than the saved one.
    package var runtimeChanged: JerdError
    /// The runtime record breaks its rules.
    package var runtimeRecordInvalid: JerdError
    /// A runtime update needs recovery, but the settings have no runtime.
    package var recoveryWithoutRuntime: JerdError
    /// A port change while a process may live.
    package var stopBeforeEditing: JerdError

    package init(
        busy: String, notLoaded: JerdError, updatePending: JerdError, runtimeMissing: JerdError,
        runtimeChanged: JerdError, runtimeRecordInvalid: JerdError, recoveryWithoutRuntime: JerdError,
        stopBeforeEditing: JerdError
    ) {
        self.busy = busy
        self.notLoaded = notLoaded
        self.updatePending = updatePending
        self.runtimeMissing = runtimeMissing
        self.runtimeChanged = runtimeChanged
        self.runtimeRecordInvalid = runtimeRecordInvalid
        self.recoveryWithoutRuntime = recoveryWithoutRuntime
        self.stopBeforeEditing = stopBeforeEditing
    }
}
