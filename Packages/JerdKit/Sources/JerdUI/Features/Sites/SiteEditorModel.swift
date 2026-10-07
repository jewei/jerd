import Foundation
import JerdFoundation
import JerdWeb
import Observation

/// The draft of the site editor sheet. It holds the reset rules: a new folder updates a name
/// and hostname that the user did not type, and every change of the folder or the document
/// root clears the document root confirmation.
@MainActor
@Observable
public final class SiteEditorModel: Identifiable {
    public let id = UUID()
    public let original: Site
    public let isNew: Bool
    public var displayName: String
    public var hostname: String
    public var projectPath: String {
        didSet {
            guard projectPath != oldValue else { return }
            suggestion = nil
            clearConfirmation()
        }
    }
    public var documentRoot: String {
        didSet { if documentRoot != oldValue { clearConfirmation() } }
    }
    public var phpSelection: PHPSelection
    public var isEnabled: Bool
    /// "I confirm that this document root can be served."
    public var isRootConfirmed = false
    public internal(set) var suggestion: DocumentRootSuggestion?
    public internal(set) var isInspecting = false
    /// A failed inspection or save, shown inline in the sheet.
    public var failure: String?
    public let runtimes: [DevelopmentRuntime]
    public let defaultRuntimeID: UUID?

    @ObservationIgnored let port: any SitesPort
    @ObservationIgnored let panels: any FilePanelPresenting

    public init(
        site: Site?, configuration: AppConfiguration, port: any SitesPort, panels: any FilePanelPresenting
    ) {
        let original = site ?? Site(displayName: "", projectPath: "", documentRoot: "", hostname: "")
        self.original = original
        isNew = site == nil
        displayName = original.displayName
        hostname = original.hostname
        projectPath = original.projectPath
        documentRoot = original.documentRoot
        phpSelection = original.phpSelection
        isEnabled = original.isEnabled
        runtimes = configuration.runtimes
        defaultRuntimeID = configuration.defaultRuntimeID
        self.port = port
        self.panels = panels
    }

    public var title: String { isNew ? "Add Site" : "Edit Site" }

    /// The text under the document root field.
    public var suggestionText: String {
        guard let suggestion else {
            return isNew ? "Select an existing project folder." : "Inspect the project to suggest its document root."
        }
        return suggestion.isLaravel
            ? "Laravel files found. The suggested document root is public."
            : "Plain PHP project. Select and confirm its document root."
    }

    /// A Laravel project served from its own `public` folder needs no confirmation.
    public var requiresConfirmation: Bool {
        !(suggestion?.isLaravel == true && suggestion?.path == documentRoot)
    }

    /// The hostname rule, inline while the user types. Nil when the field is empty or valid.
    public var hostnameMessage: String? {
        let text = hostname.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        do {
            _ = try HostnamePolicy.validate(text.lowercased())
            return nil
        } catch {
            return ErrorText.message(for: error)
        }
    }

    /// Every field is filled, the hostname is valid, and the document root is confirmed.
    public var canSave: Bool {
        let fields = [displayName, hostname, projectPath, documentRoot]
        return fields.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } && hostnameMessage == nil
            && (isRootConfirmed || !requiresConfirmation) && !isInspecting
    }

    /// Why Save is off, or nil. An invalid hostname says so at its field; an inspection shows
    /// its own progress.
    public var saveRequirement: String? {
        guard !canSave, !isInspecting, hostnameMessage == nil else { return nil }
        let missing = SaveRequirement.missing([
            (projectPath, "a project folder"), (displayName, "a display name"), (hostname, "a hostname"),
            (documentRoot, "a document root"),
        ])
        if !missing.isEmpty { return SaveRequirement.enter(missing) }
        return "To save, confirm the document root under Document Root."
    }

    /// The site that Save sends. The core validates and normalizes it again.
    public var draft: Site {
        var site = original
        site.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        site.hostname = hostname.trimmingCharacters(in: .whitespaces).lowercased()
        site.projectPath = projectPath.trimmingCharacters(in: .whitespaces)
        site.documentRoot = documentRoot.trimmingCharacters(in: .whitespaces)
        site.phpSelection = phpSelection
        site.isEnabled = isEnabled
        return site
    }

    /// The entries of the PHP selection picker.
    public var phpChoices: [PHPChoice] {
        PHPChoice.choices(runtimes: runtimes, defaultRuntimeID: defaultRuntimeID, current: original.phpSelection)
    }

    /// The confirmation that Save sends: the toggle, or a Laravel public folder.
    public var confirmsRoot: Bool { isRootConfirmed || !requiresConfirmation }

    /// Uses a chosen project folder. A name and hostname that still follow the previous folder
    /// follow the new one; typed values stay.
    public func useProjectFolder(_ path: String) {
        let previous = URL(fileURLWithPath: projectPath).lastPathComponent
        let next = URL(fileURLWithPath: path).lastPathComponent
        if displayName.isEmpty || (!projectPath.isEmpty && displayName == previous) {
            displayName = next
        }
        let previousHost = projectPath.isEmpty ? nil : HostnamePolicy.suggest(folderName: previous).value
        if hostname.isEmpty || hostname == previousHost {
            hostname = HostnamePolicy.suggest(folderName: next).value
        }
        projectPath = path
    }

    /// Asks for the project folder, then inspects it.
    public func chooseProjectFolder() async {
        let request = FilePanelRequest(kind: .folder, message: "Select the project folder.", prompt: "Select")
        guard let url = await panels.choose(request) else { return }
        useProjectFolder(url.path)
        await inspect()
    }

    /// Asks for a document root inside the project.
    public func chooseDocumentRoot() async {
        let request = FilePanelRequest(
            kind: .folder, message: "Select the document root inside the project folder.", prompt: "Select")
        guard let url = await panels.choose(request) else { return }
        documentRoot = url.path
    }

    /// Reads the project files and uses the suggested document root. It never runs project
    /// code, and it blocks no other site work. A result for a folder that the user changed
    /// meanwhile is dropped, so it never sets the root of another folder.
    public func inspect() async {
        guard !projectPath.isEmpty, !isInspecting else { return }
        isInspecting = true
        defer { isInspecting = false }
        let inspected = projectPath
        do {
            let result = try await port.suggestDocumentRoot(projectPath: inspected)
            guard projectPath == inspected else { return }
            suggestion = result
            documentRoot = result.path
            clearConfirmation()
            failure = nil
        } catch {
            if projectPath == inspected { failure = ErrorText.message(for: error) }
        }
    }

    private func clearConfirmation() {
        isRootConfirmed = false
    }
}
