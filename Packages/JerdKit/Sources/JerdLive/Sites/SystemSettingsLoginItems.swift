import ServiceManagement

/// The live opener of Login Items & Extensions: `SMAppService.openSystemSettingsLoginItems()`,
/// on the main actor because it drives System Settings.
package struct SystemSettingsLoginItems: LoginItemsOpening {
    package init() {}

    package func openLoginItems() async {
        await MainActor.run { SMAppService.openSystemSettingsLoginItems() }
    }
}
