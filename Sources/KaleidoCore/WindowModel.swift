import Foundation

public struct WindowDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let processID: Int32
    public let application: String
    public let bundleIdentifier: String
    public var title: String
    public var isMinimized: Bool
    public var isHidden: Bool
    public var isFullscreen: Bool
    public var badge: String?

    public init(id: String, processID: Int32, application: String, bundleIdentifier: String = "",
                title: String, isMinimized: Bool = false, isHidden: Bool = false,
                isFullscreen: Bool = false, badge: String? = nil) {
        self.id = id
        self.processID = processID
        self.application = application
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isFullscreen = isFullscreen
        self.badge = badge
    }

    public var displayTitle: String { title.isEmpty ? application : title }
}

public enum WindowScope: Equatable {
    case all
    case application(Int32)

    public func includes(_ window: WindowDescriptor) -> Bool {
        switch self {
        case .all: return true
        case let .application(pid): return window.processID == pid
        }
    }
}

/// MRU history is process-local and never persisted to disk.
public struct WindowHistory {
    private var sequence: UInt64 = 0
    private var focused: [String: UInt64] = [:]

    public init() {}

    public mutating func recordFocus(_ id: String) {
        sequence += 1
        focused[id] = sequence
    }

    public mutating func order(_ windows: [WindowDescriptor]) -> [WindowDescriptor] {
        let live = Set(windows.map(\.id))
        focused = focused.filter { live.contains($0.key) }
        // Preserve the WindowServer's initial order when history is not available yet.
        return windows.enumerated().sorted {
            let lhs = focused[$0.element.id, default: 0]
            let rhs = focused[$1.element.id, default: 0]
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
    }
}

public struct SwitcherSelection {
    public private(set) var windows: [WindowDescriptor] = []
    public private(set) var selectedIndex: Int?
    public var selected: WindowDescriptor? { selectedIndex.map { windows[$0] } }

    public init() {}

    public mutating func begin(windows: [WindowDescriptor], scope: WindowScope, backwards: Bool) {
        self.windows = windows.filter(scope.includes)
        guard !self.windows.isEmpty else { selectedIndex = nil; return }
        selectedIndex = backwards ? self.windows.count - 1 : min(1, self.windows.count - 1)
    }

    public mutating func move(by distance: Int) {
        guard let selectedIndex, !windows.isEmpty else { return }
        self.selectedIndex = ((selectedIndex + distance) % windows.count + windows.count) % windows.count
    }

    public mutating func select(id: String) {
        selectedIndex = windows.firstIndex { $0.id == id }
    }

    /// Keep the visible order stable as titles/states change; append newly created windows.
    public mutating func reconcile(_ current: [WindowDescriptor], scope: WindowScope) {
        let selectedID = selected?.id
        let oldIndex = selectedIndex ?? 0
        let filtered = current.filter(scope.includes)
        let byID = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(windows.map(\.id))
        windows = windows.compactMap { byID[$0.id] } + filtered.filter { !existing.contains($0.id) }
        selectedIndex = windows.firstIndex { $0.id == selectedID }
            ?? (windows.isEmpty ? nil : min(oldIndex, windows.count - 1))
    }
}
