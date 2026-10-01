import Foundation
import Security

public struct StorageRuntime: Codable, Equatable, Sendable {
    public let id: String
    public let version: String
    public let path: String
    public var executable: URL { URL(fileURLWithPath: path).appendingPathComponent("rustfs") }
    public init(id: String, version: String, path: String) {
        self.id = id; self.version = version; self.path = path
    }
}

public struct StorageBucket: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let publicRead: Bool
    public var setupComplete: Bool
    public init(name: String, publicRead: Bool = false, setupComplete: Bool = false) {
        self.name = name; self.publicRead = publicRead; self.setupComplete = setupComplete
    }
    public static func validateName(_ name: String) throws {
        guard (3...63).contains(name.utf8.count),
              name.range(of: "^[a-z0-9][a-z0-9.-]*[a-z0-9]$", options: .regularExpression) != nil,
              !name.contains(".."), !name.contains(".-"), !name.contains("-."),
              name.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) == nil,
              !["xn--", "sthree-", "amzn-s3-demo-"].contains(where: name.hasPrefix),
              !["-s3alias", "--ol-s3", ".mrap", "--x-s3", "--table-s3"].contains(where: name.hasSuffix) else {
            throw JerdError.invalid("Use 3–63 lowercase letters, numbers, dots, or hyphens. Start and end with a letter or number. Do not use an IP address, adjacent dots, or a reserved S3 name.")
        }
    }
}

public struct StorageConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var runtime: StorageRuntime?
    public var apiPort: UInt16 = 9000
    public var consolePort: UInt16 = 9001
    public var buckets: [StorageBucket] = []
    public init() {}
    public var region: String { "us-east-1" }
    public var endpoint: URL { URL(string: "http://127.0.0.1:\(apiPort)")! }
    public var consoleURL: URL { URL(string: "http://127.0.0.1:\(consolePort)/rustfs/console/")! }
    public func laravelSettings(bucket: StorageBucket, credentials: StorageCredentials) -> String {
        """
        FILESYSTEM_DISK=s3
        AWS_ACCESS_KEY_ID=\(credentials.accessKey)
        AWS_SECRET_ACCESS_KEY=\(credentials.secretKey)
        AWS_DEFAULT_REGION=\(region)
        AWS_BUCKET=\(bucket.name)
        AWS_ENDPOINT=\(endpoint.absoluteString)
        AWS_URL=\(endpoint.absoluteString)/\(bucket.name)
        AWS_USE_PATH_STYLE_ENDPOINT=true

        """
    }
    public func validate() throws {
        guard schemaVersion == 1, apiPort > 1023, consolePort > 1023, apiPort != consolePort,
              buckets.count <= 1000, Set(buckets.map(\.name)).count == buckets.count else {
            throw JerdError.invalid("Storage settings need unique buckets, two different ports from 1024 to 65535, and a supported format.")
        }
        for bucket in buckets { try StorageBucket.validateName(bucket.name) }
        if let runtime {
            guard DatabaseConfiguration.safeIdentifier(runtime.id), DatabaseConfiguration.safeIdentifier(runtime.version),
                  runtime.path.hasPrefix("/"), !runtime.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw JerdError.invalid("The RustFS runtime record is invalid.")
            }
        }
    }
}

public struct StorageCredentials: Codable, Equatable, Sendable {
    public let accessKey: String
    public let secretKey: String
    public init(accessKey: String, secretKey: String) { self.accessKey = accessKey; self.secretKey = secretKey }
    public static func generate() throws -> Self {
        func random(_ count: Int) throws -> String {
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
                throw JerdError.unavailable("Cannot generate storage credentials.")
            }
            return bytes.map { String(format: "%02X", $0) }.joined()
        }
        return try Self(accessKey: "JERD" + random(8), secretKey: random(24))
    }
    public func validate() throws {
        guard accessKey.range(of: "^[A-Z0-9]{20}$", options: .regularExpression) != nil,
              secretKey.range(of: "^[A-F0-9]{48}$", options: .regularExpression) != nil else {
            throw JerdError.corruptConfiguration("The storage credentials are invalid. The file was preserved.")
        }
    }
}

public enum StorageState: Equatable, Sendable {
    case stopped, starting, running, stopping, failed(String)
    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Ready"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }
}

public struct StorageSnapshot: Sendable {
    public let configuration: StorageConfiguration
    public let state: StorageState
    public let processID: Int32?
    public let availableBuckets: Set<String>
}

public struct StoragePaths: Sendable {
    public let root: URL
    public var data: URL { root.appendingPathComponent("data") }
    public var identity: URL { root.appendingPathComponent("runtime.json") }
    public var initialized: URL { root.appendingPathComponent("initialized.json") }
    public var format: URL { data.appendingPathComponent(".rustfs.sys/format.json") }
    public var credentials: URL { root.appendingPathComponent("credentials.json") }
    public var accessKey: URL { root.appendingPathComponent("access-key") }
    public var secretKey: URL { root.appendingPathComponent("secret-key") }
    public var activeRun: URL { root.appendingPathComponent("active-run.json") }
    public var log: URL { root.appendingPathComponent("server.log") }
    public init(root: URL) { self.root = root }
}
