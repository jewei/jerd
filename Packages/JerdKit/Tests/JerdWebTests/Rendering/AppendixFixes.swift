import Foundation
import Testing

@testable import JerdWeb

/// The documented changes from the output of the old generator (`CaddySamples`) to the new routes.
///
/// Each step names one fix. Applied to the old JSON, they must give the new JSON exactly, so no
/// other change can hide in the routes.
enum AppendixFixes {
    /// Applies every fix to the route list of one site, in place.
    ///
    /// - Parameter wellKnown: the new `.well-known` route of the same site.
    static func apply(to routes: NSMutableArray, wellKnown: Any) throws {
        // Existing visible files below `/.well-known/` are served (route 3).
        routes.insert(wellKnown, at: 2)
        // The front controller keeps its path info for `PATH_INFO`.
        let rewrite = try #require(try handlers(of: routes[4]).firstObject)
        let handlers = try handlers(of: routes[4])
        handlers.removeAllObjects()
        handlers.addObjects(from: [
            ["handler": "vars", SiteRoutePolicy.pathInfoVariable: "{http.matchers.file.remainder}"], rewrite,
        ])
        try fixPHPRoute(try #require(routes[5] as? NSMutableDictionary))
        replacePatternsAndHiddenFiles(in: routes)
    }

    private static func fixPHPRoute(_ route: NSMutableDictionary) throws {
        // The on-disk name must end in lowercase `.php`.
        let match = try #require((route["match"] as? NSArray)?.firstObject as? NSMutableDictionary)
        match["file"] = ["try_files": [SiteRoutePolicy.exactScriptPattern], "try_policy": "first_exist"]
        let proxy = try #require(try handlers(of: route).firstObject as? NSMutableDictionary)
        let transport = try #require(proxy["transport"] as? NSMutableDictionary)
        // Caddy waits longer than PHP (35 s instead of 15 s).
        #expect(transport["read_timeout"] as? Int == 15_000_000_000)
        transport["read_timeout"] = 35_000_000_000
        // Path info reaches PHP only as `PATH_INFO`, never as a file path.
        transport["env"] = ["PATH_INFO": "{http.vars.\(SiteRoutePolicy.pathInfoVariable)}"]
    }

    /// `.pht`, `.phps`, and `.phpt` are PHP-like; the static server hides more.
    private static func replacePatternsAndHiddenFiles(in value: Any) {
        if let array = value as? NSArray {
            for item in array { replacePatternsAndHiddenFiles(in: item) }
            return
        }
        guard let object = value as? NSMutableDictionary else { return }
        if let pattern = object["pattern"] as? String {
            object["pattern"] = pattern.replacingOccurrences(
                of: "\\.(php[0-9]*|phtml|phar|inc)", with: "\\.(php[0-9]*|phps|phpt|pht|phtml|phar|inc)"
            )
            .replacingOccurrences(of: "\\.(phtml|phar|inc)", with: "\\.(pht|phtml|phar|inc)")
        }
        if object["hide"] != nil { object["hide"] = SiteRoutePolicy.hiddenFiles }
        for item in object.allValues { replacePatternsAndHiddenFiles(in: item) }
    }

    private static func handlers(of route: Any) throws -> NSMutableArray {
        try #require((route as? NSDictionary)?["handle"] as? NSMutableArray)
    }
}
