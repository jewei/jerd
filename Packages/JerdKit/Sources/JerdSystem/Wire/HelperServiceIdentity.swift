import Foundation

/// The fixed names and paths of the privileged helper. Installed copies depend on every value here.
public enum HelperServiceIdentity {
    /// The Mach service name and the launchd label of the helper daemon.
    public static let machServiceName = "dev.jerd.helper"
    /// The launchd plist name for `SMAppService.daemon(plistName:)`.
    public static let plistName = "dev.jerd.helper.plist"
    /// The code-signing identifier of the app.
    public static let appIdentifier = "dev.jerd.app"
    /// The code-signing identifier of the helper.
    public static let helperIdentifier = "dev.jerd.helper"
    /// The bundle path of the helper executable, relative to `Jerd.app`.
    public static let bundleProgram = "Contents/Library/LaunchServices/JerdHelper"
    /// The bundle path of the launchd plist, relative to `Jerd.app`.
    public static let bundlePlist = "Contents/Library/LaunchDaemons/dev.jerd.helper.plist"
    /// The root-owned folder of the helper records.
    public static let recordDirectory = URL(fileURLWithPath: "/Library/Application Support/JerdHelper")
    /// The only hosts file that the helper edits.
    public static let hostsFile = URL(fileURLWithPath: "/private/etc/hosts")
}
