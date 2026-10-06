import Darwin

/// The live `execv`: PHP gets the launcher's process ID, standard streams, and exit status.
///
/// The launcher changes only the planned entries with `setenv`. All other variables pass
/// through as raw bytes, also variables that are not valid UTF-8.
public struct ProcessImage: ProcessImageReplacing {
    public init() {}

    public func replace(with plan: CLILaunchPlan) -> Int32 {
        for (name, value) in plan.environmentChanges.sorted(by: { $0.key < $1.key }) {
            guard setenv(name, value, 1) == 0 else { return errno }
        }
        let vector: [UnsafeMutablePointer<CChar>?] = plan.arguments.map { strdup($0) } + [nil]
        defer { vector.forEach { free($0) } }
        guard !vector.dropLast().contains(where: { $0 == nil }) else { return ENOMEM }
        return vector.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return EINVAL }
            execv(plan.executable, base)
            return errno
        }
    }
}
