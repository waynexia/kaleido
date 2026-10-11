import Foundation

public struct PanelGeometry: Equatable {
    public static let padding: CGFloat = 18
    public static let rowHeight: CGFloat = 40
    public static let rowGap: CGFloat = 1
    public let width: CGFloat
    public let height: CGFloat
    public let contentHeight: CGFloat

    public init(screen: CGSize, titleWidth: CGFloat, count: Int) {
        let maxWidth = max(1, screen.width * (screen.width >= screen.height ? 0.6 : 0.8))
        let minWidth = min(340, maxWidth)
        width = min(maxWidth, max(minWidth, titleWidth + 120))
        contentHeight = CGFloat(max(1, count)) * (Self.rowHeight + Self.rowGap) - Self.rowGap
        height = min(contentHeight + Self.padding * 2, max(1, screen.height * 0.8))
    }
}
