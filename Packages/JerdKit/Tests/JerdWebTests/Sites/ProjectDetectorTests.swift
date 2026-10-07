import Foundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite struct ProjectDetectorTests {
    @Test func aPlainProjectSuggestsItselfAndNeedsConfirmation() throws {
        let folder = try TemporaryDirectory(" plain")
        defer { folder.remove() }
        let suggestion = try ProjectDetector().suggestDocumentRoot(projectPath: folder.url.path)
        #expect(suggestion == DocumentRootSuggestion(path: folder.url.path, isLaravel: false))
        #expect(suggestion.requiresConfirmation)
    }

    @Test func allThreeLaravelFilesSuggestThePublicFolder() throws {
        let folder = try TemporaryDirectory(" laravel")
        defer { folder.remove() }
        for marker in ProjectDetector.laravelMarkers { try folder.file(marker, "not executable") }
        let suggestion = try ProjectDetector().suggestDocumentRoot(projectPath: folder.url.path)
        #expect(suggestion == DocumentRootSuggestion(path: folder.path("public").path, isLaravel: true))
        #expect(!suggestion.requiresConfirmation)
    }

    @Test(arguments: ProjectDetector.laravelMarkers)
    func aMissingOrFolderMarkerIsNotLaravel(_ replaced: String) throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        for marker in ProjectDetector.laravelMarkers where marker != replaced { try folder.file(marker) }
        #expect(try !ProjectDetector().suggestDocumentRoot(projectPath: folder.url.path).isLaravel)
        try folder.folder(replaced)
        #expect(try !ProjectDetector().suggestDocumentRoot(projectPath: folder.url.path).isLaravel)
    }

    @Test func detectionNeverRunsProjectCode() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let proof = folder.path("artisan-ran")
        for marker in ProjectDetector.laravelMarkers { try folder.file(marker) }
        try Data("#!/bin/sh\ntouch '\(proof.path)'\n".utf8).write(to: folder.path("artisan"))
        chmod(folder.path("artisan").path, 0o700)
        _ = try ProjectDetector().suggestDocumentRoot(projectPath: folder.url.path)
        #expect(isAbsent(proof))
    }
}
