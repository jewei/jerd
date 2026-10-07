import JerdTunnels

extension TunnelsModel {
    /// The Tunnels submenu of the menu bar: per tunnel its state, Open in Browser, Manage
    /// Tunnel…, and Stop Connector while it runs. Empty without tunnels.
    var menuItems: [MenuBarItem] {
        guard !registrations.isEmpty else { return [] }
        let tunnels = registrations.map { tunnel in
            MenuBarItem.submenu(tunnel.name, id: "tunnels.\(tunnel.id.uuidString)", items: items(for: tunnel))
        }
        return [.submenu("Tunnels", id: "tunnels", items: tunnels)]
    }

    private func items(for tunnel: TunnelRegistration) -> [MenuBarItem] {
        let key = tunnel.id.uuidString
        var items: [MenuBarItem] = [
            .text(state(of: tunnel.id).title, id: "tunnels.\(key).state"),
            .action(
                FeatureAction(id: "tunnels.\(key).open", title: "Open in Browser") { [weak self] in
                    self?.openInBrowser(tunnel)
                }),
            .action(
                FeatureAction(id: "tunnels.\(key).manage", title: "Manage Tunnel…") { [weak self] in
                    self?.shell.open(.item(.tunnel(tunnel.id)))
                }),
        ]
        if isActive(tunnel.id) {
            items.append(
                .action(
                    FeatureAction(id: "tunnels.\(key).stop", title: "Stop Connector", isEnabled: canStop(tunnel.id)) {
                        [weak self] in self?.stop(tunnel)
                    }))
        }
        return items
    }
}
