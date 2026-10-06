/// Opens Login Items & Extensions in System Settings, where the user allows the helper.
/// `SystemSettingsLoginItems` is the live type.
package protocol LoginItemsOpening: Sendable {
    func openLoginItems() async
}
