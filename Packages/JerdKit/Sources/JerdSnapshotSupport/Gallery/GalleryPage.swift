import CoreGraphics
import JerdDesign

/// One page of the component gallery. Each page is one snapshot.
package enum GalleryPage: String, CaseIterable, Sendable {
    case status
    case headers
    case rows
    case banners
    case cards
    case sheet
    case destructiveSheet = "sheet-destructive"
    case workspace
    case empty

    /// The snapshot name, for example `gallery-status`.
    package var snapshotName: String { "gallery-\(rawValue)" }

    /// Pages in a full window use both window sizes. Other pages use a canvas that fits them.
    package var sizes: [SnapshotSize] {
        switch self {
        case .workspace, .empty: SnapshotSize.windowSizes
        case .sheet: [Self.sheetCanvas(.standard)]
        case .destructiveSheet: [Self.sheetCanvas(.compact)]
        case .status: [SnapshotSize(name: "panel", width: 760, height: 600)]
        case .headers: [SnapshotSize(name: "panel", width: 760, height: 640)]
        case .rows: [SnapshotSize(name: "panel", width: 760, height: 900)]
        case .banners: [SnapshotSize(name: "panel", width: 760, height: 560)]
        case .cards: [SnapshotSize(name: "panel", width: 760, height: 720)]
        }
    }

    /// Pages with tinted fills and outlines also render with Increase Contrast.
    package var appearances: [SnapshotAppearance] {
        switch self {
        case .status, .banners, .cards: SnapshotAppearance.allCases
        default: SnapshotAppearance.standard
        }
    }

    /// Whether the page renders inside a titled window with a toolbar.
    package var usesWindow: Bool {
        self == .workspace || self == .empty
    }

    /// A sheet canvas is as tall as the sheet, which follows its content.
    private static func sheetCanvas(_ size: SheetSize) -> SnapshotSize {
        .fittingHeight(name: "sheet", width: size.width)
    }
}
