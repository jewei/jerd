import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release tool output parsers")
struct ReleaseParserTests {
    @Test("Notary results come from standard output JSON only")
    func notaryOutcome() {
        let accepted = NotaryOutcome.parse(
            standardOutput: #"{"id":"2F1D4D8E-1C55-4C55-9C55-1C551C551C55","status":"Accepted","message":"ok"}"#)
        #expect(accepted?.isAccepted == true)
        #expect(accepted?.validID == "2F1D4D8E-1C55-4C55-9C55-1C551C551C55")
        #expect(NotaryOutcome.parse(standardOutput: "Conducting pre-submission checks…") == nil)
        let invalid = NotaryOutcome.parse(standardOutput: #"{"id":"../x","status":"Invalid"}"#)
        #expect(invalid?.isAccepted == false && invalid?.validID == nil)
    }

    @Test("otool load commands give dependencies, run paths, the minimum system, and the library flag")
    func loadCommands() {
        let output = """
            /p/lib/libx.dylib:
            Load command 3
                      cmd LC_ID_DYLIB
                  cmdsize 48
                     name @rpath/libx.dylib (offset 24)
            Load command 4
                  cmd LC_BUILD_VERSION
             platform 1
                minos 14.0
            Load command 5
                      cmd LC_LOAD_DYLIB
                     name /usr/lib/libSystem.B.dylib (offset 24)
            Load command 6
                      cmd LC_LOAD_WEAK_DYLIB
                     name @loader_path/../lib/liby.dylib (offset 24)
            Load command 7
                      cmd LC_RPATH
                     path @loader_path/../lib (offset 12)
            """
        let info = MachOLoadInfo.parse(output)
        #expect(info.isLibrary)
        #expect(info.dependencies == ["/usr/lib/libSystem.B.dylib", "@loader_path/../lib/liby.dylib"])
        #expect(info.rpaths == ["@loader_path/../lib"])
        #expect(info.minimumSystem == "14.0")
    }

    @Test("Mach-O magic numbers and lipo architectures are recognized")
    func machO() {
        #expect(MachOFile.hasMachOMagic([0xCF, 0xFA, 0xED, 0xFE, 0x0C]))
        #expect(MachOFile.hasMachOMagic([0xCA, 0xFE, 0xBA, 0xBE]))
        #expect(!MachOFile.hasMachOMagic(Array("#!/bin".utf8)))
        #expect(MachOFile.architectures("x86_64 arm64\n") == ["x86_64", "arm64"])
    }

    @Test("codesign details show the identifier, team, hardened runtime, and timestamp")
    func signatureDetails() {
        let output = """
            Executable=/a/JerdCLI
            Identifier=dev.jerd.cli
            CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+7 location=embedded
            Timestamp=Oct 6, 2026 at 12:00:00
            TeamIdentifier=ABCDE12345
            """
        let details = CodeSignatureDetails.parse(output)
        #expect(details.identifier == "dev.jerd.cli" && details.teamIdentifier == "ABCDE12345")
        #expect(details.hasHardenedRuntime && details.hasTimestamp)
        let adhoc = CodeSignatureDetails.parse("Identifier=x\nCodeDirectory v=1 flags=0x20002(adhoc,linker-signed)\n")
        #expect(!adhoc.hasHardenedRuntime && !adhoc.hasTimestamp)
    }

    @Test("Runtime entitlements keep only reviewed true values and PHP gets the JIT rights")
    func entitlements() throws {
        let none = try EntitlementPolicy.entitlements(existing: Data(), isPHP: false, file: "f")
        #expect(none.isEmpty)
        let php = try EntitlementPolicy.entitlements(existing: Data(), isPHP: true, file: "php")
        #expect(php == [EntitlementPolicy.allowJIT: true, EntitlementPolicy.allowUnsignedMemory: true])
        let debug = try EntitlementPolicy.plist([EntitlementPolicy.getTaskAllow: true])
        #expect(throws: DevFailure.self) {
            try EntitlementPolicy.entitlements(existing: debug, isPHP: false, file: "f")
        }
        #expect(try EntitlementPolicy.grantsDebugging(debug, file: "f"))
        let off = try EntitlementPolicy.plist([EntitlementPolicy.disableLibraryValidation: false])
        #expect(throws: DevFailure.self) { try EntitlementPolicy.entitlements(existing: off, isPHP: false, file: "f") }
        #expect(throws: DevFailure.self) {
            try EntitlementPolicy.entitlements(existing: Data("junk".utf8), isPHP: false, file: "f")
        }
    }

    @Test("dwarfdump UUIDs are read with their architecture")
    func symbolUUIDs() {
        let output = "UUID: 1234abcd-0000-0000-0000-000000000000 (arm64) /a/Jerd\nwarning: x\n"
        #expect(
            SymbolUUIDs.parse(output) == [.init(uuid: "1234ABCD-0000-0000-0000-000000000000", architecture: "arm64")])
    }

    @Test("Only the exact tag and the exact release name count")
    func exactLookups() throws {
        let refs = """
            {"ref":"refs/tags/v0.1.0-rc1","sha":"\(ReleaseFixtures.commit)","type":"commit"}
            {"ref":"refs/tags/v0.1.01","sha":"\(ReleaseFixtures.commit)","type":"commit"}
            """
        #expect(try GitHubLookup.exactTag("v0.1.0", in: refs) == nil)
        #expect(try GitHubLookup.exactTag("v0.1.01", in: refs)?.sha == ReleaseFixtures.commit)
        let releases =
            #"{"tag":"v0.1.0-rc1","draft":false,"target":"main"}"# + "\n"
            + #"{"tag":"v0.1.0","draft":true,"target":"abc"}"#
        #expect(try GitHubLookup.release("v0.1.0", in: releases)?.draft == true)
        #expect(try GitHubLookup.release("v0.2.0", in: releases) == nil)
        #expect(throws: DevFailure.self) { try GitHubLookup.release("v0.1.0", in: "not json") }
    }

    @Test("Pull request answers are read")
    func pullRequests() throws {
        #expect(try GitHubLookup.pullRequest(#"{"number":12,"state":"MERGED"}"#).state == "MERGED")
        #expect(try GitHubLookup.pullRequests("[]").isEmpty)
        #expect(try GitHubLookup.pullRequestNumber(fromCreateOutput: "https://github.com/jewei/jerd/pull/42\n") == 42)
        #expect(throws: DevFailure.self) { try GitHubLookup.pullRequestNumber(fromCreateOutput: "done") }
    }
}
