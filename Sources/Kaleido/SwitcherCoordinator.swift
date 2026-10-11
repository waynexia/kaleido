import AppKit
import KaleidoCore

final class SwitcherCoordinator {
    let repository = WindowRepository()
    let shortcuts = GlobalShortcuts()
    let panel = SwitcherPanelController()
    private var windows: [WindowDescriptor] = []
    private var icons: [Int32: NSImage] = [:]
    private var selection = SwitcherSelection()
    private var scope: WindowScope = .all
    private var active = false
    private var pendingShow: DispatchWorkItem?
    private var outsideClick: Any?
    private var previewKeys: Any?
    private var preview = false
    var onAvailabilityChange: (() -> Void)?
    var windowCount: Int { windows.count }

    init() {
        repository.onChange = { [weak self] windows, icons in
            guard let self else { return }
            self.windows = windows
            self.icons = icons
            if self.active {
                self.selection.reconcile(windows, scope: self.scope)
                if self.selection.windows.isEmpty { self.dismiss(commit: false) }
                else if self.panel.panel.isVisible { self.panel.render(self.selection, icons: icons) }
            }
            self.onAvailabilityChange?()
        }
        repository.onActionFailure = { NSSound.beep() }
        shortcuts.onCommand = { [weak self] in self?.handle($0) }
        shortcuts.onTapDisabled = { [weak self] in self?.dismiss(commit: false) }
        shortcuts.mayBegin = { [weak self] in self?.canBegin() ?? false }
        panel.onChoose = { [weak self] id in
            self?.selection.select(id: id)
            self?.dismiss(commit: true)
        }
        panel.onAction = { [weak self] action, id in self?.repository.perform(action, on: id) }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss(commit: false)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard Accessibility.isTrusted else { return false }
        repository.start()
        return shortcuts.start()
    }

    func pause() { shortcuts.stop(); dismiss(commit: false) }

    private func canBegin() -> Bool {
        guard !windows.isEmpty else { return false }
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let remoteApps = ["com.microsoft.rdc.macos", "com.teamviewer.TeamViewer", "org.virtualbox.app.VirtualBoxVM",
                          "com.parallels.", "com.citrix.XenAppViewer", "com.citrix.receiver.icaviewer.mac",
                          "com.nicesoftware.dcvviewer", "com.vmware.fusion", "com.apple.ScreenSharing", "com.utmapp.UTM"]
        if remoteApps.contains(where: { bundle.hasPrefix($0) }),
           windows.first(where: { $0.bundleIdentifier == bundle })?.isFullscreen == true { return false }
        return true
    }

    private func handle(_ command: ShortcutCommand) {
        switch command {
        case let .begin(currentOnly, backwards):
            scope = currentOnly ? .application(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) : .all
            selection.begin(windows: windows, scope: scope, backwards: backwards)
            guard !selection.windows.isEmpty else { shortcuts.resetSession(); return }
            active = true
            pendingShow?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.active else { return }
                self.panel.show(self.selection, icons: self.icons)
            }
            pendingShow = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
            repository.requestRefresh()
        case let .move(distance):
            guard active else { return }
            selection.move(by: distance)
            if panel.panel.isVisible { panel.select(selection.selectedIndex) }
        case .commit: dismiss(commit: true)
        case .cancel: dismiss(commit: false)
        case let .act(action):
            guard active, !preview, let selected = selection.selected else { return }
            repository.perform(action, on: selected.id)
        }
    }

    private func dismiss(commit: Bool) {
        guard active else { return }
        active = false
        pendingShow?.cancel()
        pendingShow = nil
        shortcuts.resetSession()
        panel.hide(animated: true)
        if commit, !preview, let selected = selection.selected { repository.focus(selected.id) }
    }

    func showPreview() {
        preview = true
        let samples: [(String, String, String)] = [
            ("com.apple.finder", "访达", "文稿"),
            ("com.apple.Safari", "Safari", "Apple Developer"),
            ("com.apple.Terminal", "终端", "kaleido — zsh"),
            ("com.apple.TextEdit", "文本编辑", "开发笔记"),
            ("com.apple.Music", "音乐", "音乐"),
        ]
        windows = samples.enumerated().map { index, sample in
            let pid = Int32(index)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sample.0) {
                icons[pid] = NSWorkspace.shared.icon(forFile: url.path)
            }
            return WindowDescriptor(id: "preview-\(index)", processID: pid, application: sample.1,
                                    title: sample.2, isMinimized: index == 3, isHidden: index == 4)
        }
        if CommandLine.arguments.contains("--preview-overflow") {
            windows += (5..<40).map { index in
                WindowDescriptor(id: "preview-\(index)", processID: 3, application: "文本编辑",
                                 title: "文档 \(index) — " + String(repeating: "窗口标题与长文件名称 ", count: 8))
            }
        }
        selection.begin(windows: windows, scope: .all, backwards: false)
        active = true
        if CommandLine.arguments.contains("--dark") { panel.panel.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--light") { panel.panel.appearance = NSAppearance(named: .aqua) }
        panel.show(selection, icons: icons, preview: true)
        previewKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 48: self?.handle(.move(event.modifierFlags.contains(.shift) ? -1 : 1))
            case 123, 126: self?.handle(.move(-1))
            case 124, 125: self?.handle(.move(1))
            case 53: NSApp.terminate(nil)
            default: break
            }
            return nil
        }
    }
}
