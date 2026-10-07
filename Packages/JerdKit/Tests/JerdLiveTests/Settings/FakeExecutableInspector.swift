import Foundation
import JerdWeb

@testable import JerdLive

/// An inspector that returns records for the given paths without running anything.
actor FakeExecutableInspector: ExecutableInspecting {
    private(set) var inspected: [URL] = []

    func inspectPHP(cli: URL, fpm: URL) -> DevelopmentRuntime {
        inspected.append(cli)
        return SettingsSamples.php(cli.path)
    }

    func inspectCaddy(_ executable: URL) -> CaddyRuntime {
        inspected.append(executable)
        return SettingsSamples.caddy(executable.path)
    }
}
