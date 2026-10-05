/// What the link policy reads from the repository.
protocol MarkdownLinkTargets {
    /// Whether the path exists with exactly this letter case in every component.
    func exists(_ path: String) -> Bool
    func markdown(at path: String) -> String?
}
