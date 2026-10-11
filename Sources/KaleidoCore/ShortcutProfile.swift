import Foundation

public struct ShortcutBinding: Equatable {
    public let keyCode: UInt16
    public let modifiers: KeyModifiers
    public let label: String
}

public enum ShortcutProfile: String, CaseIterable {
    case standard
    case coexistence

    public var allWindows: ShortcutBinding {
        switch self {
        case .standard: return ShortcutBinding(keyCode: 48, modifiers: .control, label: "⌃ Tab")
        case .coexistence: return ShortcutBinding(keyCode: 40, modifiers: [.control, .option], label: "⌃⌥ K")
        }
    }

    public var applicationWindows: ShortcutBinding {
        switch self {
        case .standard: return ShortcutBinding(keyCode: 50, modifiers: .option, label: "⌥ `")
        case .coexistence: return ShortcutBinding(keyCode: 38, modifiers: [.control, .option], label: "⌃⌥ J")
        }
    }
}
