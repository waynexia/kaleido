import AppKit
import ServiceManagement
import KaleidoCore

final class PreferencesWindowController: NSWindowController {
    private let isPreview: Bool
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "打开辅助功能设置…", target: nil, action: nil)
    private let loginToggle = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let menuToggle = NSButton(checkboxWithTitle: "在菜单栏显示图标", target: nil, action: nil)
    private let pauseToggle = NSButton(checkboxWithTitle: "暂停快捷键", target: nil, action: nil)
    private let profileSelector = NSPopUpButton()
    private let shortcutLabel = NSTextField(wrappingLabelWithString: "")
    var onMenuVisibilityChange: ((Bool) -> Void)?
    var onPauseChange: ((Bool) -> Void)?
    var onProfileChange: ((ShortcutProfile) -> Void)?

    init(profile: ShortcutProfile, preview: Bool = false) {
        isPreview = preview
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 492),
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
        stack.addArrangedSubview(permissionButton)
        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        profileSelector.addItems(withTitles: ["Control + Tab", "Control + Option + K"])
        profileSelector.selectItem(at: ShortcutProfile.allCases.firstIndex(of: profile) ?? 0)
        profileSelector.target = self
        profileSelector.action = #selector(changeProfile)
        profileSelector.setAccessibilityLabel("窗口切换快捷键")
        stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "快捷键"), profileSelector]))
        updateShortcutLabel(profile)
        shortcutLabel.font = .systemFont(ofSize: 13)
        shortcutLabel.widthAnchor.constraint(equalToConstant: 424).isActive = true
        stack.addArrangedSubview(shortcutLabel)
        updateLoginStatus(preview ? .notRegistered : SMAppService.mainApp.status)
        loginToggle.isEnabled = !preview
        loginToggle.target = self
        loginToggle.action = #selector(toggleLogin)
        stack.addArrangedSubview(loginToggle)
        menuToggle.state = preview || UserDefaults.standard.bool(forKey: "showMenuBarIcon") ? .on : .off
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

    /// Renders the explicit preview state without changing system authorization.
    func exportPreview(to url: URL) throws {
        guard let content = window?.contentView else { return }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        guard let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                      bitsPerComponent: 8, bytesPerRow: bitmap.pixelsWide * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        var png: Data?
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            // Include the transparent content view's window background and emit
            // standard 8-bit RGB instead of AppKit's extended-range bitmap.
            let bounds = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(bounds)
            if let contentImage = bitmap.cgImage { context.draw(contentImage, in: bounds) }
            if let image = context.makeImage() {
                png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
        }
        if let png { try png.write(to: url) }
    }

    func updateStatus(trusted: Bool, listening: Bool, conflict: Bool, paused: Bool, profile: ShortcutProfile) {
        if !isPreview { updateLoginStatus(SMAppService.mainApp.status) }
        permissionButton.isHidden = trusted
        pauseToggle.state = paused ? .on : .off
        if !trusted {
            statusLabel.stringValue = "需要辅助功能权限来读取和切换窗口。请在系统设置中允许 Kaleido，完成后会自动确认。"
        } else if conflict {
            statusLabel.stringValue = "AltTab 正在使用相同的快捷键。请选择 Control + Option + K，或退出 AltTab。"
        } else if paused {
            statusLabel.stringValue = "快捷键已暂停。"
        } else if listening {
            statusLabel.stringValue = "已就绪。使用 \(profile.allWindows.label) 切换窗口，松开修饰键聚焦。"
        } else {
            statusLabel.stringValue = "无法监听快捷键。请检查辅助功能权限，或关闭安全输入后重试。"
        }
    }

    @objc private func openPermissions() { Accessibility.openSettings() }
    @objc private func toggleMenu() {
        let visible = menuToggle.state == .on
        if !isPreview { UserDefaults.standard.set(visible, forKey: "showMenuBarIcon") }
        onMenuVisibilityChange?(visible)
    }
    @objc private func togglePause() { onPauseChange?(pauseToggle.state == .on) }

    @objc private func changeProfile() {
        let profile = ShortcutProfile.allCases[profileSelector.indexOfSelectedItem]
        updateShortcutLabel(profile)
        onProfileChange?(profile)
    }

    private func updateShortcutLabel(_ profile: ShortcutProfile) {
        shortcutLabel.stringValue = "\(profile.allWindows.label)    切换窗口\n\(profile.applicationWindows.label)    切换当前应用的窗口\n⇧ / 方向键    反向 / 移动选择\nSpace    聚焦       Esc    取消\nW  关闭    M  最小化    F  全屏    Q  退出    H  隐藏"
    }

    @objc private func toggleLogin() {
        guard !isPreview else { return }
        do {
            if loginToggle.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录启动"
            alert.informativeText = "请检查系统设置中的登录项配置后重试。\n\(error.localizedDescription)"
            alert.runModal()
        }
        updateLoginStatus(SMAppService.mainApp.status)
    }

    func updateLoginStatus(_ status: SMAppService.Status) {
        // Registration awaiting user approval still exists and must remain cancellable.
        loginToggle.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginToggle.title = status == .requiresApproval ? "登录时启动（等待系统批准）" : "登录时启动"
    }
}
