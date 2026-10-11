import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController {
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "打开辅助功能设置…", target: nil, action: nil)
    private let loginToggle = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let menuToggle = NSButton(checkboxWithTitle: "在菜单栏显示图标", target: nil, action: nil)
    private let pauseToggle = NSButton(checkboxWithTitle: "暂停快捷键", target: nil, action: nil)
    var onRecheck: (() -> Void)?
    var onMenuVisibilityChange: ((Bool) -> Void)?
    var onPauseChange: ((Bool) -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 454),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Kaleido"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = NSView()
        window.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
        ])
        let title = NSTextField(labelWithString: "Kaleido")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.widthAnchor.constraint(equalToConstant: 424).isActive = true
        statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        stack.addArrangedSubview(statusLabel)
        permissionButton.target = self
        permissionButton.action = #selector(openPermissions)
        let recheck = NSButton(title: "重新检查", target: self, action: #selector(recheckPermissions))
        stack.addArrangedSubview(NSStackView(views: [permissionButton, recheck]))
        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let shortcuts = NSTextField(wrappingLabelWithString:
            "⌃ Tab    切换窗口\n⌥ `         切换当前应用的窗口\n⇧ / 方向键    反向 / 移动选择\nSpace    聚焦       Esc    取消\nW  关闭    M  最小化    F  全屏    Q  退出    H  隐藏")
        shortcuts.font = .systemFont(ofSize: 13)
        shortcuts.widthAnchor.constraint(equalToConstant: 424).isActive = true
        stack.addArrangedSubview(shortcuts)
        loginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginToggle.target = self
        loginToggle.action = #selector(toggleLogin)
        stack.addArrangedSubview(loginToggle)
        menuToggle.state = UserDefaults.standard.bool(forKey: "showMenuBarIcon") ? .on : .off
        menuToggle.target = self
        menuToggle.action = #selector(toggleMenu)
        stack.addArrangedSubview(menuToggle)
        pauseToggle.target = self
        pauseToggle.action = #selector(togglePause)
        stack.addArrangedSubview(pauseToggle)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateStatus(trusted: Bool, listening: Bool, conflict: Bool, paused: Bool) {
        permissionButton.isHidden = trusted
        pauseToggle.state = paused ? .on : .off
        if !trusted {
            statusLabel.stringValue = "需要辅助功能权限来读取和切换窗口。请在系统设置中允许 Kaleido。"
        } else if conflict {
            statusLabel.stringValue = "AltTab 正在使用相同的快捷键。退出 AltTab 后，Kaleido 会自动接管。"
        } else if paused {
            statusLabel.stringValue = "快捷键已暂停。"
        } else if listening {
            statusLabel.stringValue = "已就绪。按住 Control，再按 Tab 切换窗口。"
        } else {
            statusLabel.stringValue = "无法监听快捷键。请检查辅助功能权限，或关闭安全输入后重试。"
        }
    }

    @objc private func openPermissions() { Accessibility.openSettings() }
    @objc private func recheckPermissions() { onRecheck?() }
    @objc private func toggleMenu() {
        let visible = menuToggle.state == .on
        UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
        onMenuVisibilityChange?(visible)
    }
    @objc private func togglePause() { onPauseChange?(pauseToggle.state == .on) }

    @objc private func toggleLogin() {
        do {
            if loginToggle.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动"
            alert.informativeText = "请将 Kaleido 放入“应用程序”文件夹后重试。\n\(error.localizedDescription)"
            alert.runModal()
        }
        loginToggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
