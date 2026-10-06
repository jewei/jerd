/// The one sheet that the Databases section shows at a time. A single sheet value lets the
/// retained list hand over to the restore editor without two sheets racing.
public enum DatabasesSheet: String, Identifiable, Sendable {
    case editor
    case retained
    case restore

    public var id: String { rawValue }
}
