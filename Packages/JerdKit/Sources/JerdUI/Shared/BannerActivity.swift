/// Global work that shows in the operation banner at the bottom of the window, on every page.
/// Use it only for work that affects more than its own page, for example a stop of all sites.
public struct BannerActivity {
    public let message: String
    /// A fraction from 0 to 1, or nil when the length is unknown.
    public let progress: Double?
    /// The Stop button of the banner, when the work can stop.
    public let stop: FeatureAction?

    public init(message: String, progress: Double? = nil, stop: FeatureAction? = nil) {
        self.message = message
        self.progress = progress
        self.stop = stop
    }
}
