import Foundation
import JerdDevKit

// The `jerd-dev` executable behind `./dev`. All logic is in JerdDevKit.
let status = await DevMain.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(status)
