/// The ports of the data-service features and the command-line tools section, as one value
/// of `AppDependencies`.
public struct ServicePorts {
    public var databases: any DatabasesPort
    public var storage: any StoragePort
    public var mail: any MailPort
    public var commandLineTools: any CommandLineToolsPort

    public init(
        databases: any DatabasesPort, storage: any StoragePort, mail: any MailPort,
        commandLineTools: any CommandLineToolsPort
    ) {
        self.databases = databases
        self.storage = storage
        self.mail = mail
        self.commandLineTools = commandLineTools
    }
}
