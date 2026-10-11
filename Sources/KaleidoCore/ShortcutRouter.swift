import Foundation

public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

public enum WindowAction: Equatable { case close, minimize, fullscreen, quit, hide }
public enum ShortcutCommand: Equatable {
    case begin(currentApplicationOnly: Bool, backwards: Bool)
    case move(Int)
    case commit
    case cancel
    case act(WindowAction)
}

public struct ShortcutResult: Equatable {
    public let consume: Bool
    public let command: ShortcutCommand?
    public init(_ consume: Bool = false, _ command: ShortcutCommand? = nil) {
        self.consume = consume
        self.command = command
    }
}

/// Pure state machine: the event tap only routes input; it never enumerates windows.
public struct ShortcutRouter {
    public private(set) var hold: KeyModifiers?
    private var captured = Set<UInt16>()
    private var previousModifiers: KeyModifiers = []
    private var shiftWithoutTab = false

    public init() {}

    public mutating func reset() { hold = nil; shiftWithoutTab = false }

    public mutating func modifiersChanged(_ modifiers: KeyModifiers) -> ShortcutResult {
        defer { previousModifiers = modifiers }
        guard let hold else { return ShortcutResult() }
        guard modifiers.contains(hold) else {
            reset()
            return ShortcutResult(false, .commit)
        }
        if modifiers.contains(.shift), !previousModifiers.contains(.shift) { shiftWithoutTab = true }
        if !modifiers.contains(.shift), previousModifiers.contains(.shift), shiftWithoutTab {
            shiftWithoutTab = false
            return ShortcutResult(false, .move(-1))
        }
        return ShortcutResult()
    }

    public mutating func keyUp(_ code: UInt16) -> ShortcutResult {
        ShortcutResult(captured.remove(code) != nil)
    }

    public mutating func keyDown(_ code: UInt16, modifiers: KeyModifiers, isRepeat: Bool = false) -> ShortcutResult {
        previousModifiers = modifiers
        let backwards = modifiers.contains(.shift)
        if hold == nil {
            let base = modifiers.subtracting(.shift)
            let all = code == 48 && base == .control
            let current = code == 50 && base == .option
            guard all || current else { return ShortcutResult() }
            hold = all ? .control : .option
            captured.insert(code)
            return ShortcutResult(true, .begin(currentApplicationOnly: current, backwards: backwards))
        }
        let command: ShortcutCommand?
        switch code {
        case 48, 50:
            shiftWithoutTab = false
            command = .move(backwards ? -1 : 1)
        case 123, 126: command = .move(-1)
        case 124, 125: command = .move(1)
        case 49, 36: command = .commit; reset()
        case 53: command = .cancel; reset()
        case 13: command = isRepeat ? nil : .act(.close)
        case 46: command = isRepeat ? nil : .act(.minimize)
        case 3: command = isRepeat ? nil : .act(.fullscreen)
        case 12: command = isRepeat ? nil : .act(.quit)
        case 4: command = isRepeat ? nil : .act(.hide)
        default: command = nil
        }
        // Never leak switcher keystrokes to the previously focused application.
        captured.insert(code)
        return ShortcutResult(true, command)
    }
}
