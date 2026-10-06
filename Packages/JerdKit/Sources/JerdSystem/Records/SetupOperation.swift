/// The transactions that the helper journals. The raw values are saved in `pending.json`.
enum SetupOperation: String, CaseIterable, Sendable {
    case configure = "Configure HTTPS"
    case remove = "Remove HTTPS"
}
