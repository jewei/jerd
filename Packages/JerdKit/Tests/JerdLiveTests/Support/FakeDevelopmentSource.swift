import JerdFoundation
import JerdWeb

@testable import JerdLive

/// The bundled PHP and Caddy without a payload: set answers and an install counter.
actor FakeDevelopmentSource: DevelopmentRuntimeSource {
    private(set) var installCount = 0
    let needed: Bool
    let records: DevelopmentRuntimeRecords
    let failure: JerdError?

    init(
        needed: Bool = true,
        records: DevelopmentRuntimeRecords = DevelopmentRuntimeRecords(
            php: SampleWeb.php(cli: "/bundled/php"), caddy: SampleWeb.caddy(path: "/bundled/caddy")),
        failure: JerdError? = nil
    ) {
        self.needed = needed
        self.records = records
        self.failure = failure
    }

    func isNeeded(for configuration: AppConfiguration) -> Bool { needed }

    func install() throws -> DevelopmentRuntimeRecords {
        installCount += 1
        if let failure { throw failure }
        return records
    }
}
