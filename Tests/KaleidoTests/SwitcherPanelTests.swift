import AppKit
import XCTest
import KaleidoCore
@testable import Kaleido

final class SwitcherPanelTests: XCTestCase {
    private func samples(_ count: Int = 40) -> [WindowDescriptor] {
        (0..<count).map { WindowDescriptor(id: "fixture-\($0)", processID: 1, application: "Fixture", title: "Window \($0)") }
    }

    private func scrollView(_ panel: SwitcherPanelController) throws -> NSScrollView {
        try XCTUnwrap(panel.panel.contentView?.subviews.first as? NSScrollView)
    }

    func testRefreshReusesRowsAndPreservesManualScrollAndHover() throws {
        XCTAssertTrue(Thread.isMainThread)
        _ = NSApplication.shared
        let panel = SwitcherPanelController()
        var windows = samples()
        var selection = SwitcherSelection()
        selection.begin(windows: windows, scope: .all, backwards: false)
        panel.render(selection, icons: [:])
        let scroll = try scrollView(panel)
        let list = try XCTUnwrap(scroll.documentView)
        let originalRows = list.subviews
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        let offset = scroll.contentView.bounds.origin
        XCTAssertGreaterThan(offset.y, 0)
        windows[10].title = "Updated fixture"
        windows[10].isMinimized = true
        let row = originalRows[10]
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                        timestamp: 0, windowNumber: 0, context: nil,
                                                        eventNumber: 0, trackingNumber: 0, userData: nil))
        row.mouseEntered(with: event)
        let controls = try XCTUnwrap(row.subviews.compactMap { $0 as? NSStackView }.first)
        XCTAssertFalse(controls.isHidden)
        selection.reconcile(windows, scope: .all)
        panel.render(selection, icons: [:])
        XCTAssertEqual(scroll.contentView.bounds.origin, offset)
        XCTAssertEqual(list.subviews.count, originalRows.count)
        XCTAssertTrue(zip(list.subviews, originalRows).allSatisfy { $0 === $1 })
        XCTAssertFalse(controls.isHidden)
        XCTAssertTrue(row.accessibilityLabel()?.contains("Updated fixture，已最小化") == true)
    }

    func testKeyboardSelectionRevealsOffscreenRowAndRemovalReusesSurvivors() throws {
        _ = NSApplication.shared
        let panel = SwitcherPanelController()
        let windows = samples()
        var selection = SwitcherSelection()
        selection.begin(windows: windows, scope: .all, backwards: false)
        panel.render(selection, icons: [:])
        let scroll = try scrollView(panel)
        let list = try XCTUnwrap(scroll.documentView)
        let survivor = list.subviews[39]
        selection.select(id: "fixture-39")
        panel.select(selection.selectedIndex)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
        selection.reconcile([windows[39]], scope: .all)
        panel.render(selection, icons: [:])
        XCTAssertEqual(list.subviews.count, 1)
        XCTAssertTrue(list.subviews.first === survivor)
        XCTAssertTrue(survivor.isAccessibilitySelected())
    }
}
