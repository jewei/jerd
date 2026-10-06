import Foundation

/// The absolute paths of the macOS programs that the runtime, release, and check commands use.
///
/// These programs ship with macOS at fixed paths, so plans use the paths directly and tests compare
/// them as plain values. Programs that come from Xcode run through `Toolchain.xcrun`.
enum SystemProgram {
    static let codesign = URL(filePath: "/usr/bin/codesign")
    static let ditto = URL(filePath: "/usr/bin/ditto")
    static let hdiutil = URL(filePath: "/usr/bin/hdiutil")
    static let spctl = URL(filePath: "/usr/sbin/spctl")
    static let installNameTool = URL(filePath: "/usr/bin/install_name_tool")
    static let otool = URL(filePath: "/usr/bin/otool")
    static let lipo = URL(filePath: "/usr/bin/lipo")
    static let rsync = URL(filePath: "/usr/bin/rsync")
    static let make = URL(filePath: "/usr/bin/make")
    static let security = URL(filePath: "/usr/bin/security")
    static let swVers = URL(filePath: "/usr/bin/sw_vers")
    static let defaults = URL(filePath: "/usr/bin/defaults")
    static let shell = URL(filePath: "/bin/sh")
}
