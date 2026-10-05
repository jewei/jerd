import SwiftUI

/// A vertical stack of page banners with a bottom inset. With no banners it takes no space,
/// so a page without messages keeps the same header height.
struct BannerStack: Layout {
    var spacing: CGFloat = Spacing.small
    var bottomInset: CGFloat = Spacing.large

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let total = heights.reduce(0, +) + spacing * CGFloat(subviews.count - 1) + bottomInset
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let proposal = ProposedViewSize(width: bounds.width, height: nil)
            let height = subview.sizeThatFits(proposal).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}
