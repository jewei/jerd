import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

@testable import JerdDatabases

@Suite struct DatabaseFormatTests {
    static let mysqlID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func servicesJSONOfOlderBuildsDecodesAndEncodesToTheSameBytes() throws {
        let bytes = try golden("services.json")
        let configuration = try JSONDecoder().decode(DatabaseConfiguration.self, from: bytes)
        try configuration.validateForSave()
        #expect(configuration.services.first?.id == Self.mysqlID)
        #expect(configuration.services.first?.port == 3_306)
        #expect(configuration.runtimes.map(\.engine) == [.mysql, .redis])
        #expect(try JSONFileFormat.settings.makeEncoder().encode(configuration) == bytes)
    }

    @Test(arguments: ["schemaVersion", "runtimes", "services"])
    func everyServicesKeyIsRequired(_ key: String) throws {
        let object = try jsonObject(try golden("services.json")).mutableCopy() as! NSMutableDictionary
        object.removeObject(forKey: key)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(DatabaseConfiguration.self, from: data) }
    }

    @Test func markersOfOlderBuildsDecodeAndEncodeToTheSameObjects() throws {
        let identityBytes = try golden("runtime.json")
        let identity = try JSONDecoder().decode(DatabaseIdentity.self, from: identityBytes)
        #expect(
            identity
                == DatabaseIdentity(
                    serviceID: Self.mysqlID, runtimeID: "mysql-8.4.11-arm64", engine: .mysql, version: "8.4.11"))
        let encoded = try JSONFileFormat.compact.makeEncoder().encode(identity)
        #expect(try jsonObject(encoded) == jsonObject(identityBytes))

        let credentialBytes = try golden("credentials.json")
        let credentials = try JSONDecoder().decode(DatabaseCredentials.self, from: credentialBytes)
        try credentials.validate()
        #expect(try JSONFileFormat.compact.makeEncoder().encode(credentials) == credentialBytes)

        let removedBytes = try golden("removed-registration.json")
        let removed = try JSONDecoder().decode(RemovedRegistration.self, from: removedBytes)
        #expect(removed.isValid && removed.service.name == "Main MySQL")
        #expect(removed.runtime.path.hasPrefix("/Users/me/Library/Application Support/Jerd"))
        #expect(try jsonObject(JSONFileFormat.compact.makeEncoder().encode(removed)) == jsonObject(removedBytes))
    }

    @Test func credentialsAre64LowercaseHexCharacters() throws {
        let credentials = try DatabaseCredentials.generate()
        #expect(HexEncoding.isHex(credentials.password, length: 64))
        try credentials.validate()
        #expect(try DatabaseCredentials.generate() != credentials)
        for bad in [
            "", String(repeating: "A", count: 64), String(repeating: "a", count: 63), String(repeating: "g", count: 64),
        ] {
            #expect(throws: DatabaseMessages.credentialsInvalid) { try DatabaseCredentials(password: bad).validate() }
        }
    }

    @Test func aFailingRandomSourceGivesTheCredentialMessage() {
        let failing = SecretGenerator { _ in false }
        #expect(throws: DatabaseMessages.credentialsUnavailable) { try DatabaseCredentials.generate(using: failing) }
    }

    @Test func aCredentialFileIsPrivateAndAnInvalidOneIsPreserved() throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let file = directory.path("credentials.json")
        let credentials = try DatabaseCredentials.generate()
        try credentials.write(to: file)
        #expect(mode(file) == 0o600)
        #expect(try DatabaseCredentials.read(from: file) == credentials)
        try write("{\"password\":\"short\"}", to: file)
        #expect(throws: DatabaseMessages.credentialsInvalid) { try DatabaseCredentials.read(from: file) }
        #expect(text(file) == "{\"password\":\"short\"}")
    }

    @Test func laravelSettingsNameTheEngineAccount() {
        let password = String(repeating: "a", count: 64)
        #expect(
            DatabaseConnection(engine: .redis, port: 6_380, password: password).environment
                == "REDIS_HOST=127.0.0.1\nREDIS_PORT=6380\nREDIS_USERNAME=default\nREDIS_PASSWORD=\(password)\n")
        #expect(
            DatabaseConnection(engine: .mysql, port: 3_307, password: password).environment
                == "DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=3307\nDB_DATABASE=jerd\nDB_USERNAME=jerd\n"
                + "DB_PASSWORD=\(password)\n")
        #expect(
            DatabaseConnection(engine: .postgresql, port: 5_433, password: password).environment
                == "DB_CONNECTION=pgsql\nDB_HOST=127.0.0.1\nDB_PORT=5433\nDB_DATABASE=postgres\nDB_USERNAME=jerd\n"
                + "DB_PASSWORD=\(password)\n")
    }
}
