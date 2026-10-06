import Foundation
import Testing

/// The bytes of `Fixtures/Golden/<name>`: objects that older Jerd builds wrote.
///
/// `services.json` has the exact bytes of older builds (the settings format). The other markers
/// were written with a plain `JSONEncoder()`, whose key order is not stable, so tests compare
/// them as objects (`jsonObject`), never as bytes.
func golden(_ name: String) throws -> Data {
    let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try Data(contentsOf: folder.appendingPathComponent("Golden").appendingPathComponent(name))
}

/// The JSON object of `data`, for comparisons that ignore key order.
func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}
