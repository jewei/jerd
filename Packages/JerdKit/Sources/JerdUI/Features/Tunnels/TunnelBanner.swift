/// One error banner of a tunnel page.
struct TunnelBanner: Equatable {
    let title: String
    let message: String
    /// True when this banner carries Edit Tunnel…, because an edit can fix the failure.
    let offersEdit: Bool
}
