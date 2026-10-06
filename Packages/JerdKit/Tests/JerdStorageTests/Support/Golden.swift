import Foundation
import Testing

/// The bytes of `Fixtures/Golden/<name>`: files exactly as older Jerd builds wrote them.
func golden(_ name: String) throws -> Data {
    let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try Data(contentsOf: folder.appendingPathComponent("Golden").appendingPathComponent(name))
}

/// The JSON object of `data`, for comparisons that ignore key order.
func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}
