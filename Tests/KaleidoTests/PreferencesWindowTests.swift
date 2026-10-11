import AppKit
import ServiceManagement
import XCTest
@testable import Kaleido

final class PreferencesWindowTests: XCTestCase {
    private func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    func testPendingLoginRegistrationRemainsCheckedAndCanReflectApprovalOrRemoval() throws {
        _ = NSApplication.shared
        let settings = PreferencesWindowController(profile: .standard, preview: true)
        let content = try XCTUnwrap(settings.window?.contentView)
        let login = try XCTUnwrap(buttons(in: content).first { $0.title == "登录时启动" })
        settings.updateLoginStatus(.requiresApproval)
        XCTAssertEqual(login.state, .on)
        XCTAssertTrue(login.title.contains("等待系统批准"))
        settings.updateLoginStatus(.enabled)
        XCTAssertEqual(login.state, .on)
        XCTAssertEqual(login.title, "登录时启动")
        settings.updateLoginStatus(.notRegistered)
        XCTAssertEqual(login.state, .off)
    }

    func testPreviewControlsCannotChangeSavedMenuPreferenceOrRegisterLoginItem() throws {
        _ = NSApplication.shared
        let previous = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? NSNumber
        let settings = PreferencesWindowController(profile: .standard, preview: true)
        let content = try XCTUnwrap(settings.window?.contentView)
        let controls = buttons(in: content)
        let login = try XCTUnwrap(controls.first { $0.title == "登录时启动" })
        let menu = try XCTUnwrap(controls.first { $0.title == "在菜单栏显示图标" })
        XCTAssertFalse(login.isEnabled)
        XCTAssertEqual(menu.state, .on, "Preview state is deterministic regardless of saved preferences")
        menu.performClick(nil)
        XCTAssertEqual(menu.state, .off)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "showMenuBarIcon") as? NSNumber, previous)
    }
}
