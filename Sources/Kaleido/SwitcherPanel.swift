import AppKit
import KaleidoCore

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class WindowRow: NSView {
    private(set) var descriptor: WindowDescriptor
    var onChoose: ((String) -> Void)?
    var onAction: ((WindowAction, String) -> Void)?
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let controls = NSStackView()
    private var tracking: NSTrackingArea?
    private var sourceImage: NSImage?
    private var configured = false
    var selected = false {
        didSet {
            guard selected != oldValue else { return }
            needsDisplay = true
            setAccessibilitySelected(selected)
        }
    }
    private var hovered = false { didSet { controls.isHidden = !hovered; status.isHidden = hovered; needsLayout = true } }

    init(window: WindowDescriptor, image: NSImage?, width: CGFloat) {
        self.descriptor = window
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: PanelGeometry.rowHeight))
        wantsLayer = true
        layer?.cornerRadius = 10
        icon.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        status.alignment = .right
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = 6
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.isHidden = true
        for (symbol, help, tag) in [("xmark.circle.fill", "关闭窗口", 0), ("minus.circle.fill", "最小化窗口", 1),
                                     ("plus.circle.fill", "切换全屏", 2)] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!,
                                  target: self, action: #selector(controlClicked(_:)))
            button.isBordered = false
            button.contentTintColor = [NSColor.systemRed, .systemYellow, .systemGreen][tag]
            button.tag = tag
            button.toolTip = help
            button.setAccessibilityLabel(help)
            button.widthAnchor.constraint(equalToConstant: 16).isActive = true
            controls.addArrangedSubview(button)
        }
        [icon, titleLabel, status, controls, badge].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(window: window, image: image)
    }

    func update(window: WindowDescriptor, image: NSImage?) {
        guard !configured || descriptor != window || sourceImage !== image else { return }
        configured = true
        descriptor = window
        sourceImage = image
        icon.image = image ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        titleLabel.stringValue = window.displayTitle
        let states = [(window.isMinimized, "minus.circle"), (window.isHidden, "eye.slash"),
                      (window.isFullscreen, "arrow.up.left.and.arrow.down.right")].filter(\.0)
        let statusText = NSMutableAttributedString()
        for (_, symbol) in states {
            let attachment = NSTextAttachment()
            attachment.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            statusText.append(NSAttributedString(attachment: attachment))
            statusText.append(NSAttributedString(string: " "))
        }
        status.attributedStringValue = statusText
        badge.stringValue = window.badge ?? ""
        badge.isHidden = window.badge?.isEmpty != false
        toolTip = "\(window.application) — \(window.displayTitle)"
        let stateNames = [(window.isMinimized, "已最小化"), (window.isHidden, "已隐藏"), (window.isFullscreen, "全屏")]
            .filter(\.0).map(\.1).joined(separator: "，")
        setAccessibilityLabel("\(window.application)，\(window.displayTitle)\(stateNames.isEmpty ? "" : "，" + stateNames)")
        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 7, y: 7, width: 26, height: 26)
        let trailing = hovered ? CGFloat(78) : max(7, status.fittingSize.width + 7)
        titleLabel.frame = NSRect(x: 35, y: 10, width: max(0, bounds.width - 35 - trailing), height: 20)
        status.frame = NSRect(x: bounds.width - 78, y: 11, width: 68, height: 19)
        controls.frame = NSRect(x: bounds.width - 73, y: 10, width: 62, height: 20)
        let badgeWidth = max(13, min(32, badge.fittingSize.width))
        badge.frame = NSRect(x: 28 - badgeWidth / 2, y: 22, width: badgeWidth, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = selected
            ? (dark ? NSColor.black.withAlphaComponent(0.60) : NSColor.lightGray.withAlphaComponent(0.70)).cgColor
            : NSColor.clear.cgColor
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
        if let window {
            hovered = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { onChoose?(descriptor.id) }
    override func accessibilityPerformPress() -> Bool { onChoose?(descriptor.id); return true }

    @objc private func controlClicked(_ sender: NSButton) {
        onAction?([.close, .minimize, .fullscreen][sender.tag], descriptor.id)
    }
}

final class SwitcherPanelController {
    let panel: SwitcherPanel
    private let background = NSVisualEffectView()
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private var rows: [WindowRow] = []
    private var fadeGeneration = 0
    private var screen: NSScreen?
    var onChoose: ((String) -> Void)?
    var onAction: ((WindowAction, String) -> Void)?

    init() {
        panel = SwitcherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.title = "窗口"
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isMovable = false
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 23
        background.layer?.masksToBounds = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = list
        scroll.contentView.drawsBackground = false
        background.addSubview(scroll)
        panel.contentView = background
        panel.setAccessibilityLabel("窗口切换器")
        panel.setAccessibilitySubrole(.standardWindow)
    }

    func show(_ selection: SwitcherSelection, icons: [Int32: NSImage], preview: Bool = false) {
        fadeGeneration += 1
        panel.alphaValue = 1
        screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        render(selection, icons: icons, revealSelection: true)
        panel.orderFrontRegardless()
        if preview { NSApp.activate(ignoringOtherApps: true); panel.makeKey() }
    }

    func render(_ selection: SwitcherSelection, icons: [Int32: NSImage], revealSelection: Bool = false) {
        guard let screen = screen ?? NSScreen.main else { return }
        let geometry = PanelGeometry(screen: screen.frame.size, count: selection.windows.count)
        let frame = NSRect(x: screen.visibleFrame.midX - geometry.width / 2,
                           y: screen.visibleFrame.midY - geometry.height / 2,
                           width: geometry.width, height: geometry.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        background.frame = NSRect(origin: .zero, size: frame.size)
        scroll.frame = background.bounds.insetBy(dx: PanelGeometry.padding, dy: PanelGeometry.padding)
        scroll.contentView.setFrameSize(scroll.bounds.size)
        let width = scroll.contentSize.width - PanelGeometry.rowGap * 2
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: geometry.contentHeight)
        let previousSelection = rows.first { $0.selected }?.descriptor.id
        var reusable = Dictionary(uniqueKeysWithValues: rows.map { ($0.descriptor.id, $0) })
        rows = selection.windows.enumerated().map { index, window in
            let row = reusable.removeValue(forKey: window.id)
                ?? WindowRow(window: window, image: icons[window.processID], width: width)
            row.update(window: window, image: icons[window.processID])
            row.frame = NSRect(x: PanelGeometry.rowGap, y: PanelGeometry.rowGap + CGFloat(index) * (PanelGeometry.rowHeight + PanelGeometry.rowGap),
                               width: width, height: PanelGeometry.rowHeight)
            row.onChoose = { [weak self] in self?.onChoose?($0) }
            row.onAction = { [weak self] in self?.onAction?($0, $1) }
            if row.superview == nil { list.addSubview(row) }
            return row
        }
        reusable.values.forEach { $0.removeFromSuperview() }
        // Reorder accessibility children without detaching reused views or losing hover state.
        list.setAccessibilityChildren(rows)
        select(selection.selectedIndex, reveal: revealSelection || previousSelection != selection.selected?.id)
    }

    func select(_ index: Int?, reveal: Bool = true) {
        for (offset, row) in rows.enumerated() { row.selected = offset == index }
        if reveal, let index, rows.indices.contains(index) {
            list.scrollToVisible(rows[index].frame)
            NSAccessibility.post(element: rows[index], notification: .focusedUIElementChanged)
        }
    }

    func hide(animated: Bool) {
        fadeGeneration += 1
        let generation = fadeGeneration
        guard animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        }
    }

    /// Deterministic view rendering for local visual QA; captures only our own fixture view.
    func exportPreview(to url: URL) throws {
        background.layoutSubtreeIfNeeded()
        guard let bitmap = background.bitmapImageRepForCachingDisplay(in: background.bounds) else { return }
        background.cacheDisplay(in: background.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: url) }
    }
}
