/// A command-line argument that `SnapshotOptions.parse(_:)` cannot accept.
package enum SnapshotOptionsError: Error, Equatable, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)

    package var description: String {
        switch self {
        case .missingValue(let option): "The option \(option) needs a value."
        case .unknownArgument(let argument): "The argument \(argument) is not known."
        }
    }
}
