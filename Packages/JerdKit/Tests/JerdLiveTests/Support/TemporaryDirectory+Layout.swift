import JerdFoundation
import JerdTestSupport

extension TemporaryDirectory {
    /// A data layout in `Jerd/` below the folder. Nothing is created until a test writes.
    var layout: DataLayout { DataLayout(root: url.appendingPathComponent("Jerd", isDirectory: true)) }
}
