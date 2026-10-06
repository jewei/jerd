import Darwin

/// The live `execve`: PHP gets the launcher's process ID, standard streams, and exit status.
///
/// The argument vector and the environment are the plan's raw bytes. The launcher never calls
/// `setenv` and never decodes a user argument or an environment entry.
package struct ProcessImage: ProcessImageReplacing {
    package init() {}

    package func replace(with plan: CLILaunchPlan) -> Int32 {
        Self.withVectors(of: plan) { path, arguments, environment in
            execve(path, arguments, environment)
            return errno
        }
    }

    /// Calls `body` with the C vectors that `execve` gets for `plan`. Tests give the same vectors
    /// to `posix_spawn`, so they run exactly what the launcher runs.
    package static func withVectors<Result>(
        of plan: CLILaunchPlan,
        _ body: (String, UnsafePointer<UnsafeMutablePointer<CChar>?>, UnsafePointer<UnsafeMutablePointer<CChar>?>)
            -> Result
    ) -> Result {
        CStrings.withVector(plan.arguments) { arguments in
            CStrings.withVector(plan.environment.entries) { environment in
                body(plan.executable, arguments, environment)
            }
        }
    }
}
