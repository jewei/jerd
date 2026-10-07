import Foundation

extension DatabaseConfiguration {
    /// The longest service name, counted after trimming.
    public static let nameLimit = 80

    /// The structural rules of every load and save.
    ///
    /// A saved file that breaks them was not written by Jerd, so a load reports it as corrupt and
    /// preserves it. A user typo never reaches this point: the registry checks ports and names first.
    public func validate() throws {
        guard schemaVersion == Self.supportedVersion, runtimes.count <= Self.recordLimit,
            services.count <= Self.recordLimit, Self.isUnique(runtimes.map(\.id)), Self.isUnique(services.map(\.id)),
            Self.isUnique(services.map(\.port))
        else { throw DatabaseMessages.unsupportedSettings }
        guard runtimes.allSatisfy(\.isValid) else { throw DatabaseMessages.runtimeRecordInvalid }
        for service in services {
            guard Self.isValidName(service.name), service.port >= 1_024 else { throw DatabaseMessages.serviceInvalid }
            _ = try runtime(for: service)
        }
    }

    /// The rules of a save: the structural rules and unique trimmed names.
    public func validateForSave() throws {
        try validate()
        guard Self.isUnique(services.map { Self.trimmed($0.name) }) else { throw DatabaseMessages.duplicateName }
    }

    /// 1 to 80 characters after trimming, without control characters.
    public static func isValidName(_ name: String) -> Bool {
        let trimmed = trimmed(name)
        return !trimmed.isEmpty && trimmed.count <= nameLimit
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// The name without leading and trailing white space and newlines.
    public static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUnique<Value: Hashable>(_ values: [Value]) -> Bool {
        Set(values).count == values.count
    }
}
