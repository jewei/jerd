import Foundation
import Darwin
import JerdCore

do {
    let command = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    guard ["php", "composer", "laravel"].contains(command) else {
        throw JerdError.invalid("Install Jerd's php, composer, and laravel commands with Scripts/Development/setup-php-cli.py.")
    }
    let directory = JSONConfigurationStore.applicationDirectory
    let config = try JSONConfigurationStore.loadConfiguration(from: directory)
    let selection = try CLIRuntimeSelection.resolve(configuration: config,
        workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let executable = selection.runtime.cliPath
    guard FileManager.default.isExecutableFile(atPath: executable) else {
        throw JerdError.unavailable("PHP \(selection.runtime.version) selected for \(selection.site?.hostname ?? "the default") is unavailable: \(executable)")
    }
    let userArguments = Array(CommandLine.arguments.dropFirst())
    let userEnvironment = ProcessInfo.processInfo.environment
    let explicitTrust = ["PHPRC", "SSL_CERT_FILE", "SSL_CERT_DIR", "CURL_CA_BUNDLE"].contains { userEnvironment[$0] != nil }
    let usesOwnINI = command == "php" && PHPConfigurationPolicy.hasINISelection(userArguments)
    let caBundle = explicitTrust || usesOwnINI ? nil : try PHPTrustBundle().forCLI(applicationDirectory: directory)
    let policy = try PHPConfigurationPolicy.cli(arguments: userArguments, command: command,
        directory: directory.appendingPathComponent("runtimes/configuration"), environment: userEnvironment, caBundle: caBundle)
    var arguments = [executable] + policy.arguments
    for (key, value) in policy.environment { setenv(key, value, 1) }
    if command != "php" {
        let tools = try JSONDecoder().decode(CLICompanions.self,
            from: Data(contentsOf: directory.appendingPathComponent("runtimes/cli-tools.json")))
        let script = command == "composer" ? tools.composerPath : tools.laravelPath
        guard FileManager.default.isReadableFile(atPath: script) else {
            throw JerdError.unavailable("The Jerd \(command) tool is unavailable. Open Jerd to install its bundled tools.")
        }
        arguments.append(script)
    }
    arguments.append(contentsOf: CommandLine.arguments.dropFirst())
    // Child commands must resolve php/composer through the same project selector.
    let bin = directory.appendingPathComponent("bin").path
    setenv("PATH", bin + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"), 1)
    let pointers = arguments.map { strdup($0) } + [nil]
    defer { for pointer in pointers { free(pointer) } }
    pointers.withUnsafeBufferPointer { buffer in _ = execv(executable, buffer.baseAddress!) }
    throw JerdError.process("Cannot run PHP: \(String(cString: strerror(errno)))")
} catch {
    FileHandle.standardError.write(Data("Jerd: \(error.localizedDescription)\n".utf8))
    exit(1)
}
