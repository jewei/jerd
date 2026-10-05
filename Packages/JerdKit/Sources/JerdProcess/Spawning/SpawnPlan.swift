import Foundation
import JerdFoundation

/// Everything `posix_spawn` receives, computed from a request without any side effect.
public struct SpawnPlan: Equatable, Sendable {
    /// Where a child descriptor comes from.
    public enum DescriptorSource: Equatable, Sendable {
        /// `/dev/null`, opened read-only.
        case nullDevice
        /// The log file or the redacting pipe.
        case output
        /// The inherited HTTP listener.
        case httpListener
        /// The inherited HTTPS listener.
        case httpsListener
    }

    /// One child descriptor and its source. All other descriptors close on exec.
    public struct DescriptorAction: Equatable, Sendable {
        public let target: Int32
        public let source: DescriptorSource
    }

    /// The variables every child receives unless the request replaces them. `HOME` is the working folder.
    public static let baseEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]

    public let executablePath: String
    /// `argv`, starting with the executable path.
    public let arguments: [String]
    /// `envp` as `NAME=value` strings, sorted by name.
    public let environment: [String]
    public let workingDirectory: String
    /// Descriptor actions in the order they run.
    public let descriptors: [DescriptorAction]

    /// Builds the plan. Nothing from Jerd's own environment is inherited.
    /// - Throws: `.invalid` for a relative executable, an unsafe variable name, or a NUL character.
    public init(request: ProcessRequest) throws {
        guard request.executable.isFileURL, request.executable.path.hasPrefix("/") else {
            throw JerdError.invalid("Use an absolute executable path: \(request.executable.path)")
        }
        var variables = Self.baseEnvironment
        variables["HOME"] = request.workingDirectory.path
        variables.merge(request.environment) { _, requested in requested }
        guard variables.keys.allSatisfy({ !$0.isEmpty && !$0.contains("=") }) else {
            throw JerdError.invalid("Process environment names cannot be empty or contain \"=\".")
        }
        executablePath = request.executable.path
        arguments = [request.executable.path] + request.arguments
        environment = variables.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        workingDirectory = request.workingDirectory.path
        guard (arguments + environment + [workingDirectory]).allSatisfy({ !$0.contains("\0") }) else {
            throw JerdError.invalid("Process arguments cannot contain NUL characters.")
        }
        var actions = [
            DescriptorAction(target: 0, source: .nullDevice), DescriptorAction(target: 1, source: .output),
            DescriptorAction(target: 2, source: .output),
        ]
        if request.listeners != nil {
            actions.append(DescriptorAction(target: InheritedListeners.httpDescriptor, source: .httpListener))
            actions.append(DescriptorAction(target: InheritedListeners.httpsDescriptor, source: .httpsListener))
        }
        descriptors = actions
    }
}
