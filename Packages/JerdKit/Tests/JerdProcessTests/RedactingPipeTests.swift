import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdProcess

@Suite struct RedactingPipeTests {
    @Test func bytesWrittenIntoThePipeReachTheLogRedacted() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let log = ProcessLogFile(url: folder.path("pipe.log"))
        let handle = try log.create()
        let pipe = try RedactingPipe(log: handle.fileDescriptor, values: ["hidden-value"])
        let child = dup(pipe.writer)
        pipe.closeParentWriter()
        pipe.closeParentWriter()
        #expect(DescriptorIO.writeAll(Data("one hidden-".utf8), to: child) == 0)
        #expect(DescriptorIO.writeAll(Data("value two\n".utf8), to: child) == 0)
        close(child)
        pipe.finish()
        pipe.finish()
        #expect(text(log.url) == "one [redacted] two\n")
        #expect(pipe.writeFailure == nil)
    }

    @Test func aFailedLogWriteIsReported() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try Data().write(to: folder.path("read-only.log"))
        let readOnly = open(folder.path("read-only.log").path, O_RDONLY)
        defer { close(readOnly) }
        let pipe = try RedactingPipe(log: readOnly, values: ["x"])
        let child = dup(pipe.writer)
        pipe.closeParentWriter()
        #expect(DescriptorIO.writeAll(Data("output".utf8), to: child) == 0)
        close(child)
        pipe.finish()
        #expect(pipe.writeFailure == SystemError.describe(EBADF))
    }

    @Test func tooManySecretsAreRefusedBeforeAPipeIsCreated() throws {
        #expect(throws: JerdError.invalid("The log redaction configuration is too large.")) {
            try RedactingPipe(log: STDERR_FILENO, values: (0..<33).map(String.init))
        }
    }
}
