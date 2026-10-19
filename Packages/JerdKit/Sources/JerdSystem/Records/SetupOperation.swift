/// The transactions that the helper journals. The raw values are saved in `pending.json`.
enum SetupOperation: String, CaseIterable, Sendable {
    case configure = "Configure HTTPS"
    case remove = "Remove HTTPS"
    /// Replaces the CA of a setup with Jerd's CA that may sign only `.test` names. An earlier
    /// helper reads a journal of this operation as corrupt and preserves it.
    case replaceCA = "Replace HTTPS CA"
}
