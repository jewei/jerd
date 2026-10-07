/// File and folder names shared by the service folders. They are part of the compatibility contract.
public enum ServiceFileName {
    /// The `flock` target that guards one service folder.
    public static let lock = "service.lock"
    /// The saved identity of a running service process.
    public static let activeRun = "active-run.json"
    /// The output of the running service process.
    public static let log = "server.log"
    /// The output of the previous run.
    public static let previousLog = "server.previous.log"
    /// Settings, encoded with `JSONFileFormat.settings`.
    public static let settings = "settings.json"
    /// The bytes of the settings before the last save.
    public static let previousSettings = "settings.previous.json"
    /// The runtime identity that owns the data.
    public static let runtimeIdentity = "runtime.json"
    /// The marker of completed data initialization.
    public static let initializedMarker = "initialized.json"
    /// Service credentials.
    public static let credentials = "credentials.json"
    /// The journal of an unfinished runtime update.
    public static let runtimeUpdateJournal = "runtime-update.json"
    /// Copies of data and settings made before runtime updates.
    public static let runtimeBackups = "runtime-backups"
    /// The service data folder.
    public static let data = "data"
}
