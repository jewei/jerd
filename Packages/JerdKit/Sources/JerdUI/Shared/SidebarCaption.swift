/// The one caption rule of every sidebar footer: nothing for an empty list, because the page
/// shows the empty state; else the count, and "· N running" only while something runs.
enum SidebarCaption {
    /// - Parameters:
    ///   - singular: The noun for one item, for example "site".
    ///   - plural: The noun for other counts, for example "sites".
    ///   - running: The running items, or nil for items that do not run, such as buckets.
    static func text(count: Int, singular: String, plural: String, running: Int? = nil) -> String? {
        guard count > 0 else { return nil }
        let items = "\(count) \(count == 1 ? singular : plural)"
        guard let running, running > 0 else { return items }
        return "\(items) · \(running) running"
    }
}
