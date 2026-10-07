import Foundation

/// The exact commands that build the reviewed XZ library for RustFS.
///
/// The extracted source keeps the modification times of the archive (see JerdArchive). Thus `make`
/// does not try to run Automake, which the fixed `PATH` does not contain.
///
/// The environment is fixed, so the build does not use Homebrew or other tools from `PATH`. The
/// deployment target comes from `Configuration/Base.xcconfig`, the same as the app. The compiler
/// and the linker get it twice, as `MACOSX_DEPLOYMENT_TARGET` and as `-mmacosx-version-min`, so a
/// build step that drops the environment still does not target the macOS of the build Mac.
/// The library gets the install name `@rpath/liblzma.5.dylib` instead of the build folder path, and
/// an ad hoc signature; the release signs it again with Developer ID.
struct XZBuildPlan: Equatable, Sendable {
    static let libraryName = "liblzma.5.dylib"
    static let licenseName = "XZ-LICENSE.txt"
    static let upstreamLicense = "COPYING.0BSD"

    /// The unpacked source folder, without the `xz-<version>` root.
    let source: URL
    /// The `--prefix` folder of `make install`.
    let install: URL
    let deploymentTarget: String
    let processors: Int
    let environment: [String: String]

    init(source: URL, install: URL, deploymentTarget: String, processors: Int, inherited: [String: String]) {
        self.source = source
        self.install = install
        self.deploymentTarget = deploymentTarget
        self.processors = max(1, processors)
        var environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "MACOSX_DEPLOYMENT_TARGET": deploymentTarget,
            "CC": "/usr/bin/clang",
            "CFLAGS": "-O2 -arch arm64 -mmacosx-version-min=\(deploymentTarget)",
            "LDFLAGS": "-arch arm64 -mmacosx-version-min=\(deploymentTarget)",
        ]
        for name in ["HOME", "TMPDIR", "DEVELOPER_DIR"] {
            if let value = inherited[name], !value.isEmpty { environment[name] = value }
        }
        self.environment = environment
    }

    static let configureOptions = [
        "--disable-static", "--enable-shared", "--disable-xz", "--disable-xzdec", "--disable-lzmadec",
        "--disable-lzmainfo", "--disable-scripts", "--disable-doc", "--disable-nls",
        "--disable-dependency-tracking",
    ]

    /// configure, make, and make install, in this order.
    var buildSteps: [Invocation] {
        [
            step(
                source.appending(path: "configure"), ["--prefix=\(install.path)"] + Self.configureOptions),
            step(SystemProgram.make, ["-j\(processors)"]),
            step(SystemProgram.make, ["install"]),
        ]
    }

    /// The built library inside the install folder.
    var builtLibrary: URL { install.appending(path: "lib/\(Self.libraryName)") }
    var upstreamLicenseFile: URL { source.appending(path: Self.upstreamLicense) }

    /// Sets the install name of the copied library, then signs it ad hoc, because the change breaks
    /// the linker signature.
    static func finishingSteps(library: URL) -> [Invocation] {
        [
            Invocation(
                executable: SystemProgram.installNameTool,
                arguments: ["-id", "@rpath/\(libraryName)", library.path], timeout: TimeLimit.probe),
            Invocation(
                executable: SystemProgram.codesign, arguments: ["--force", "--sign", "-", library.path],
                timeout: TimeLimit.codeSigning),
        ]
    }

    private func step(_ executable: URL, _ arguments: [String]) -> Invocation {
        Invocation(
            executable: executable, arguments: arguments, environment: environment, workingDirectory: source,
            timeout: TimeLimit.supportBuild)
    }
}
