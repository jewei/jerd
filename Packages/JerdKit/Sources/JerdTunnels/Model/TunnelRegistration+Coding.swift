import Foundation

extension TunnelRegistration {
    private enum CodingKeys: String, CodingKey {
        case id, name, hostname, siteID, originURL, startOnLaunch, restartOnFailure, metricsPort, routing
    }

    /// Earlier registrations keep their remote routes and all required keys stay required.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        hostname = try values.decode(String.self, forKey: .hostname)
        siteID = try values.decodeIfPresent(UUID.self, forKey: .siteID)
        originURL = try values.decodeIfPresent(String.self, forKey: .originURL)
        startOnLaunch = try values.decode(Bool.self, forKey: .startOnLaunch)
        restartOnFailure = try values.decode(Bool.self, forKey: .restartOnFailure)
        metricsPort = try values.decode(UInt16.self, forKey: .metricsPort)
        routing = try values.decodeIfPresent(TunnelRouting.self, forKey: .routing) ?? .cloudflare
    }

    /// Omitting the default routing key preserves the exact format of earlier registrations.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(hostname, forKey: .hostname)
        try values.encodeIfPresent(siteID, forKey: .siteID)
        try values.encodeIfPresent(originURL, forKey: .originURL)
        try values.encode(startOnLaunch, forKey: .startOnLaunch)
        try values.encode(restartOnFailure, forKey: .restartOnFailure)
        try values.encode(metricsPort, forKey: .metricsPort)
        if routing != .cloudflare { try values.encode(routing, forKey: .routing) }
    }
}
