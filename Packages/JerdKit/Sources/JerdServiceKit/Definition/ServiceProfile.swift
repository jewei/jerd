import Darwin
import Foundation
import JerdFoundation

/// The fixed facts of one managed instance.
public struct ServiceProfile: Sendable {
    /// The name in user messages, for example the database service name or "Mailpit".
    public var name: String
    /// The runtime ID saved in the run record.
    public var runtimeID: String
    /// The run record and the lock file that guards the instance folder.
    public var record: RecordLocation
    /// An existing owned folder that contains the instance folder. Missing folders between the two
    /// are created with mode 0700.
    public var containingDirectory: URL
    /// The server log and its previous copy.
    public var log: ServiceLog
    /// The loopback TCP ports of the server, in the order that they are checked.
    public var ports: [UInt16]
    /// The graceful stop signal, also saved in the run record.
    public var stopSignal: Int32
    public var messages: ServiceMessages

    public init(
        name: String, runtimeID: String, record: RecordLocation, containingDirectory: URL, log: ServiceLog,
        ports: [UInt16], stopSignal: Int32 = SIGTERM, messages: ServiceMessages
    ) {
        self.name = name
        self.runtimeID = runtimeID
        self.record = record
        self.containingDirectory = containingDirectory
        self.log = log
        self.ports = ports
        self.stopSignal = stopSignal
        self.messages = messages
    }

    /// The instance folder: the working folder of every command and the server.
    public var folder: URL { record.folder }
}
