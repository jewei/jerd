import JerdRuntimes

/// How `InMemoryRuntimeInventory.install` answers.
public enum InstallBehavior: Sendable {
    /// Reports the steps, then returns the build.
    case succeed
    /// Throws this user message.
    case fail(String)
    /// Reports the progress, then waits until the task is cancelled.
    case suspend(RuntimeInstallProgress)
}
