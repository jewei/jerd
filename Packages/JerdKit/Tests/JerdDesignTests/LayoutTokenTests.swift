import CoreGraphics
import Testing

@testable import JerdDesign

@Suite("Layout tokens")
struct LayoutTokenTests {
    @Test("Window sizes match the minimum and default main window")
    func windowSizes() {
        #expect(WindowMetrics.minimumSize == CGSize(width: 820, height: 540))
        #expect(WindowMetrics.standardSize == CGSize(width: 980, height: 660))
    }

    @Test(
        "Header text, section edges, and form margins share one centered column",
        arguments: [300.0, 620, 760, 820, 980, 1600])
    func columnsShareOneEdge(width: CGFloat) {
        let columns = PageMetrics.columns(forWidth: width)
        #expect(columns.contentWidth <= PageMetrics.maximumContentWidth)
        #expect(columns.sectionInset == PageMetrics.formInset + columns.formMargin)
        #expect(columns.textInset == columns.sectionInset + PageMetrics.rowInset)
        #expect(columns.formMargin >= 0)
        #expect(abs(columns.sectionInset * 2 + columns.contentWidth - width) <= 1)
    }

    @Test(
        "Card content starts on the same text column as the page title and form rows",
        arguments: [620.0, 760, 980])
    func cardContentSharesTextColumn(width: CGFloat) {
        let columns = PageMetrics.columns(forWidth: width)
        #expect(columns.sectionInset + PageMetrics.cardInset == columns.textInset)
    }

    @Test("A narrow page uses only the system form inset")
    func narrowPageHasNoExtraMargin() {
        let columns = PageMetrics.columns(forWidth: 620)
        #expect(columns.formMargin == 0)
        #expect(columns.contentWidth == 580)
        #expect(columns.textInset == 30)
    }

    @Test("A wide page centers a column of the maximum width")
    func widePageCentersColumn() {
        let columns = PageMetrics.columns(forWidth: 980)
        #expect(columns.contentWidth == 680)
        #expect(columns.sectionInset == 150)
    }

    @Test("The column stays narrower than the 704 pt limit of system grouped forms")
    func columnIsNarrowerThanSystemLimit() {
        #expect(PageMetrics.maximumContentWidth < 704)
    }

    @Test("Spacing values follow a strictly increasing scale")
    func spacingScaleIncreases() {
        let scale = [
            Spacing.hairline, Spacing.tight, Spacing.small, Spacing.medium, Spacing.large, Spacing.extraLarge,
            Spacing.section, Spacing.page,
        ]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }

    @Test("Radii increase from small to large, and icon tiles scale with their side")
    func radii() {
        #expect(Radius.small < Radius.medium && Radius.medium < Radius.large)
        #expect(Radius.iconTile(side: 64) == 17)
        #expect(Radius.iconTile(side: 28) == 8)
    }

    @Test("Increase Contrast always strengthens outlines")
    func contrastStrokesAreStronger() {
        #expect(Opacity.tintStrokeIncreasedContrast > Opacity.tintStroke)
        #expect(Opacity.cardStrokeIncreasedContrast > Opacity.cardStroke)
    }

    @Test("Every sheet size has a maximum height at least its minimum, under the smallest window")
    func sheetSizes() {
        for size in [SheetSize.compact, .standard, .wide] {
            #expect(size.maximumHeight >= size.minimumHeight)
            #expect(size.maximumHeight < WindowMetrics.minimumSize.height)
        }
        #expect(SheetSize(width: 400, minimumHeight: 300, maximumHeight: 100).maximumHeight == 300)
        #expect(SheetSize.compact.width < SheetSize.standard.width)
        #expect(SheetSize.standard.width < SheetSize.wide.width)
    }
}
