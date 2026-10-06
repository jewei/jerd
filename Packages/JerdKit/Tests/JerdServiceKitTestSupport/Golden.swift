import Foundation
import JerdFoundation

/// The bytes of `Fixtures/Golden/<name>` in `bundle`: files exactly as older Jerd builds wrote them.
package func goldenFixture(_ name: String, in bundle: Bundle) throws -> Data {
    guard let folder = bundle.url(forResource: "Fixtures", withExtension: nil) else {
        throw JerdError.unavailable("The golden fixtures are missing.")
    }
    return try Data(contentsOf: folder.appendingPathComponent("Golden").appendingPathComponent(name))
}

/// The JSON object of `data`, for comparisons that ignore key order.
package func jsonObject(_ data: Data) throws -> NSDictionary {
    guard let object = try JSONSerialization.jsonObject(with: data) as? NSDictionary else {
        throw JerdError.invalid("The data is not a JSON object.")
    }
    return object
}
