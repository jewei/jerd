extension Duration {
    /// Whole seconds, for messages such as "120 s".
    var formattedSeconds: String {
        "\(components.seconds) s"
    }
}
