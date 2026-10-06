import JerdSnapshotSupport
import SwiftUI
import Testing

@testable import JerdDesign

/// Renders components offscreen and measures the pixels, for rules that only an image shows.
@Suite("Component rendering")
@MainActor
struct ComponentRenderingTests {
    private func render(
        _ view: some View, width: CGFloat, height: CGFloat? = nil, appearance: SnapshotAppearance = .light
    ) async throws -> PixelMeasure {
        let size = SnapshotSize(name: "test", width: width, height: height)
        let image = try await SnapshotRenderer().render(
            view.background(Color(nsColor: .windowBackgroundColor)), size: size, appearance: appearance,
            chrome: .content)
        return PixelMeasure(image: image)
    }

    @Test(
        "The destructive confirm label has at least 4.5:1 contrast on its bezel",
        arguments: [SnapshotAppearance.light, .dark])
    func destructiveConfirmContrast(appearance: SnapshotAppearance) async throws {
        let confirmation = SheetConfirmation("Delete Backup", isDestructive: true) {}
        let pixels = try await render(
            SheetConfirmButton(confirmation: confirmation, isEnabled: true).frame(width: 160, height: 40), width: 160,
            height: 40, appearance: appearance)
        let middle = pixels.height / 2
        let bezel = pixels.dominantColor(columns: 120..<200, rows: middle - 4..<middle + 4)
        let label = pixels.maximumContrast(columns: 80..<240, rows: middle - 12..<middle + 12, against: bezel)
        #expect(label >= 4.5, "The label contrast is \(label):1 in \(appearance)")
    }

    @Test("The operation message uses the primary text color", arguments: [SnapshotAppearance.light, .dark])
    func operationMessageIsPrimary(appearance: SnapshotAppearance) async throws {
        let pixels = try await render(
            OperationBanner("Downloading PHP 8.5.1…", progress: 0.4), width: 400, appearance: appearance)
        let background = pixels.dominantColor(columns: 0..<pixels.width, rows: 0..<pixels.height)
        // The text starts after the 96 pt progress bar; the bar's accent color stays under 7:1.
        let text = pixels.maximumContrast(
            columns: 260..<pixels.width - 40, rows: 4..<pixels.height - 4, against: background)
        #expect(text >= 7, "The message contrast is \(text):1 in \(appearance)")
    }

    /// The text of a check result must reach 4.5:1 (WCAG AA). Green text reached 1.8:1 in light.
    /// Increase Contrast resolves the primary label color to pure black or white, so it only gains.
    @Test(
        "A check result text has at least 4.5:1 contrast", arguments: [SnapshotAppearance.light, .dark])
    func checkResultContrast(appearance: SnapshotAppearance) async throws {
        for passed in [true, false] {
            let pixels = try await render(
                CheckResultLabel("Passed at start", passed: passed).padding(8)
                    .frame(width: 240, height: 40, alignment: .leading), width: 240, height: 40,
                appearance: appearance)
            let background = pixels.dominantColor(columns: 0..<pixels.width, rows: 0..<pixels.height)
            // The text starts after 8 pt padding, a 16 pt symbol, and the label spacing.
            let text = pixels.maximumContrast(
                columns: 40 * 2..<pixels.width, rows: 0..<pixels.height, against: background)
            #expect(text >= 4.5, "The result contrast is \(text):1 in \(appearance), passed: \(passed)")
        }
    }

    @Test("The message text starts at the same place for every kind")
    func messageTextStartIsFixed() async throws {
        var images: [PixelMeasure] = []
        for kind in MessageKind.allCases {
            images.append(try await render(InlineMessage("Same text", kind: kind).padding(8), width: 300, height: 40))
        }
        // Symbol column: 8 pt padding, 16 pt symbol, 8 pt spacing.
        let textColumns = (8 + Int(InlineMessage.symbolWidth) + 8) * 2..<images[0].width
        for image in images.dropFirst() {
            #expect(image.sameColumns(textColumns, as: images[0]))
        }
    }

    @Test("A one-line banner has one height with and without its buttons")
    func bannerHeightIsFixed() async throws {
        let banners: [InlineMessage] = [
            InlineMessage("Bucket studio-assets is ready.", kind: .success, style: .banner),
            InlineMessage("Bucket studio-assets is ready.", kind: .success, style: .banner, dismiss: {}),
            InlineMessage(
                "Bucket studio-assets is ready.", kind: .success, style: .banner,
                action: PageAction("Show") {}, dismiss: {}),
        ]
        var heights: [Int] = []
        for banner in banners {
            heights.append(try await render(banner, width: 500).height)
        }
        #expect(Set(heights).count == 1, "Banner heights: \(heights)")
    }

    @Test("The copy toast in the detail column never covers the operation banner")
    func copyToastStaysAboveOperationBanner() async throws {
        let operation = OperationBanner("Stopping PHP-FPM and Caddy…")
        let bannerHeight = try await render(operation, width: 400).height
        let message = CopyFeedbackMessage("Copied site URL")
        let withToast = try await render(
            Color.clear.detailColumn(copyFeedback: .constant(message), operation: operation), width: 400, height: 240)
        let withoutToast = try await render(
            Color.clear.detailColumn(copyFeedback: .constant(nil), operation: operation), width: 400, height: 240)
        let bannerRows = withToast.height - bannerHeight..<withToast.height
        #expect(withToast.sameRows(bannerRows, as: withoutToast))
        #expect(!withToast.sameRows(0..<withToast.height, as: withoutToast), "The toast did not render")
    }

    @Test("A sheet takes the height of its content, between its minimum and maximum")
    func sheetHeightFollowsContent() async throws {
        let short = try await render(sheet(rows: 3), width: SheetSize.standard.width).height
        let taller = try await render(sheet(rows: 8), width: SheetSize.standard.width).height
        let long = try await render(sheet(rows: 60), width: SheetSize.standard.width).height
        let empty = try await render(sheet(rows: 0), width: SheetSize.standard.width).height
        #expect(taller > short)
        #expect(long == Int(SheetSize.standard.maximumHeight * SnapshotRenderer.scale))
        #expect(empty == Int(SheetSize.standard.minimumHeight * SnapshotRenderer.scale))
    }

    private func sheet(rows: Int) -> some View {
        SheetScaffold(
            "Edit Site", confirmation: SheetConfirmation("Save", perform: {}), cancel: {},
            content: {
                Section {
                    ForEach(0..<rows, id: \.self) { row in
                        LabeledContent("Row \(row)", value: "Value")
                    }
                }
            })
    }
}
