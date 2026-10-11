import Foundation

public struct PanelGeometry: Equatable {
    public static let padding: CGFloat = 18
    public static let rowHeight: CGFloat = 40
    public static let rowGap: CGFloat = 1
    public let width: CGFloat
    public let height: CGFloat
    public let contentHeight: CGFloat

    public init(screen: CGSize, count: Int) {
        // The title layout has a stable width regardless of the current window titles.
        let available = (screen.width * (screen.width >= screen.height ? 0.6 : 0.8) - Self.padding * 2).rounded()
        let rowWidth = max(1, (available * 0.9 - Self.rowGap * 2).rounded())
        width = min(max(1, screen.width), rowWidth + (Self.padding + Self.rowGap) * 2)
        contentHeight = CGFloat(max(1, count)) * (Self.rowHeight + Self.rowGap) + Self.rowGap
        height = min(contentHeight + Self.padding * 2, max(1, (screen.height * 0.8).rounded()))
    }
}
