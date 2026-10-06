/// One folder of `runtime-updates/`: a usable build, or a folder that cannot be used and why.
///
/// One bad folder does not hide the others.
public enum ManagedRuntimeListing: Hashable, Sendable {
    case runtime(ManagedRuntime)
    /// A folder with a receipt that cannot be read, or that belongs to another architecture.
    case unusable(folder: String, reason: String)

    /// The build, when the folder is usable.
    public var runtime: ManagedRuntime? {
        if case .runtime(let runtime) = self { return runtime }
        return nil
    }
}
