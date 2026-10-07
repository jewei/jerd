import Foundation
import JerdServiceKitTestSupport

/// The bytes of `Fixtures/Golden/<name>` of this test target.
func golden(_ name: String) throws -> Data { try goldenFixture(name, in: .module) }
