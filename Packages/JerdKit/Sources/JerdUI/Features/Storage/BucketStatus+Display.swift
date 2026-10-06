import JerdDesign
import JerdStorage

extension BucketStatus {
    /// The status of a bucket row and the bucket page. While storage is not running, the tone
    /// follows the storage state.
    public var displayStatus: DisplayStatus {
        switch self {
        case .setupIncomplete, .missing: DisplayStatus(title, tone: .attention)
        case .ready: DisplayStatus(title, tone: .ready)
        case .serviceNotRunning(let state): DisplayStatus(title, tone: state.displayStatus.tone)
        }
    }
}
