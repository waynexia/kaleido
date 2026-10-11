import XCTest
@testable import KaleidoCore

final class SwitcherTests: XCTestCase {
    private func window(_ id: String, pid: Int32 = 1, title: String = "") -> WindowDescriptor {
        WindowDescriptor(id: id, processID: pid, application: "App", title: title)
    }

    func testFirstSelectionWrapAndSingleWindow() {
        var state = SwitcherSelection()
        state.begin(windows: [window("a"), window("b"), window("c")], scope: .all, backwards: false)
        XCTAssertEqual(state.selected?.id, "b")
        state.move(by: 2)
        XCTAssertEqual(state.selected?.id, "a")
        state.move(by: -1)
        XCTAssertEqual(state.selected?.id, "c")
        state.begin(windows: [window("a")], scope: .all, backwards: false)
        state.move(by: -10)
        XCTAssertEqual(state.selected?.id, "a")
        state.begin(windows: [], scope: .all, backwards: true)
        state.move(by: 1)
        XCTAssertNil(state.selected)
    }

    func testScopeAndReverseStart() {
        var state = SwitcherSelection()
        state.begin(windows: [window("a"), window("b", pid: 2), window("c")], scope: .application(1), backwards: true)
        XCTAssertEqual(state.windows.map(\.id), ["a", "c"])
        XCTAssertEqual(state.selected?.id, "c")
    }

    func testReconcilePreservesSelectionAndVisibleOrderThenHandlesClosedWindow() {
        var state = SwitcherSelection()
        state.begin(windows: [window("a"), window("b"), window("c")], scope: .all, backwards: false)
        state.reconcile([window("c"), window("b", title: "Updated"), window("a"), window("d")], scope: .all)
        XCTAssertEqual(state.windows.map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(state.selected?.title, "Updated")
        state.reconcile([window("a"), window("c"), window("d")], scope: .all)
        XCTAssertEqual(state.selected?.id, "c")
        state.reconcile([], scope: .all)
        XCTAssertNil(state.selected)
    }

    func testHistoryUsesStableInitialOrderAndPrunesDeadWindows() {
        var history = WindowHistory()
        let windows = [window("a"), window("b"), window("c")]
        XCTAssertEqual(history.order(windows).map(\.id), ["a", "b", "c"])
        history.recordFocus("c")
        history.recordFocus("b")
        XCTAssertEqual(history.order(windows).map(\.id), ["b", "c", "a"])
        _ = history.order([window("a")])
        XCTAssertEqual(history.order(windows).map(\.id), ["a", "b", "c"])
    }

    func testQuickSwitchCommitsOnControlReleaseWithoutAVisiblePanel() {
        var router = ShortcutRouter()
        XCTAssertEqual(router.keyDown(48, modifiers: .control).command, .begin(currentApplicationOnly: false, backwards: false))
        XCTAssertTrue(router.keyUp(48).consume)
        XCTAssertEqual(router.modifiersChanged([]).command, .commit)
        XCTAssertNil(router.hold)
        XCTAssertFalse(router.keyDown(48, modifiers: []).consume)
    }

    func testCancelCannotCommitOnLaterReleaseAndSwallowsPairedKeyUp() {
        var router = ShortcutRouter()
        _ = router.keyDown(48, modifiers: .control)
        XCTAssertEqual(router.keyDown(53, modifiers: .control).command, .cancel)
        XCTAssertTrue(router.keyUp(53).consume)
        XCTAssertNil(router.modifiersChanged([]).command)
    }

    func testReverseNavigationAndShiftAlone() {
        var router = ShortcutRouter()
        _ = router.keyDown(48, modifiers: .control)
        XCTAssertEqual(router.modifiersChanged([.control, .shift]).command, .move(-1))
        XCTAssertNil(router.keyDown(48, modifiers: [.control, .shift]).command)
        XCTAssertEqual(router.keyDown(48, modifiers: [.control, .shift]).command, .move(-1))
        XCTAssertNil(router.modifiersChanged(.control).command)
        XCTAssertEqual(router.modifiersChanged([.control, .shift]).command, .move(-1))
        XCTAssertNil(router.modifiersChanged(.control).command)
    }

    func testSecondaryShortcutModifiersAndDestructiveRepeat() {
        var router = ShortcutRouter()
        XCTAssertFalse(router.keyDown(48, modifiers: [.control, .command]).consume)
        XCTAssertEqual(router.keyDown(50, modifiers: .option).command, .begin(currentApplicationOnly: true, backwards: false))
        XCTAssertEqual(router.keyDown(13, modifiers: .option).command, .act(.close))
        XCTAssertNil(router.keyDown(13, modifiers: .option, isRepeat: true).command)
        XCTAssertTrue(router.keyDown(0, modifiers: .option).consume)
        XCTAssertEqual(router.keyDown(49, modifiers: .option).command, .commit)
    }

    func testGeometryMatchesMeasuredTitlePanelAndClampsOverflow() {
        let geometry = PanelGeometry(screen: CGSize(width: 1512, height: 982), count: 100)
        XCTAssertEqual(geometry.width, 820)
        XCTAssertEqual(geometry.height, 786)
        XCTAssertGreaterThan(geometry.contentHeight, geometry.height)
        let tiny = PanelGeometry(screen: CGSize(width: 240, height: 200), count: 1)
        XCTAssertLessThanOrEqual(tiny.width, 240)
        XCTAssertLessThanOrEqual(tiny.height, 200)
    }

    func testInitialReverseChordAndReleaseOfUnrelatedModifier() {
        var router = ShortcutRouter()
        XCTAssertEqual(router.keyDown(48, modifiers: [.control, .shift]).command,
                       .begin(currentApplicationOnly: false, backwards: true))
        XCTAssertNil(router.modifiersChanged(.control).command)
        XCTAssertEqual(router.modifiersChanged([]).command, .commit)
    }

    func testWindowActionsAndArrowNavigation() {
        var router = ShortcutRouter()
        _ = router.keyDown(48, modifiers: .control)
        for (key, action) in [(UInt16(13), WindowAction.close), (46, .minimize), (3, .fullscreen), (12, .quit), (4, .hide)] {
            XCTAssertEqual(router.keyDown(key, modifiers: .control).command, .act(action))
            XCTAssertTrue(router.keyUp(key).consume)
        }
        XCTAssertEqual(router.keyDown(126, modifiers: .control).command, .move(-1))
        XCTAssertEqual(router.keyDown(125, modifiers: .control).command, .move(1))
    }
}
