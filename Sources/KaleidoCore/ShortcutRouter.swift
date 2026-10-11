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
    public let profile: ShortcutProfile
    public private(set) var hold: KeyModifiers?
    private var cycleKey: UInt16?
    private var captured = Set<UInt16>()
    private var previousModifiers: KeyModifiers = []
    private var shiftAlreadyMoved = false

    public init(profile: ShortcutProfile = .standard) { self.profile = profile }

    public mutating func reset(clearCapturedKeys: Bool = false) {
        hold = nil
        cycleKey = nil
        shiftAlreadyMoved = false
        if clearCapturedKeys { captured.removeAll() }
    }

    public mutating func modifiersChanged(_ modifiers: KeyModifiers) -> ShortcutResult {
        defer { previousModifiers = modifiers }
        guard let hold else { return ShortcutResult() }
        guard modifiers.contains(hold) else {
            reset()
            return ShortcutResult(false, .commit)
        }
        if modifiers.contains(.shift), !previousModifiers.contains(.shift) {
            shiftAlreadyMoved = true
            return ShortcutResult(false, .move(-1))
        }
        if !modifiers.contains(.shift) { shiftAlreadyMoved = false }
        return ShortcutResult()
    }

    public mutating func keyUp(_ code: UInt16, modifiers: KeyModifiers? = nil) -> ShortcutResult {
        let consumed = captured.remove(code) != nil
        if let modifiers, let hold, !modifiers.contains(hold) {
            reset()
            return ShortcutResult(consumed, .commit)
        }
        return ShortcutResult(consumed)
    }

    public mutating func keyDown(_ code: UInt16, modifiers: KeyModifiers, isRepeat: Bool = false,
                                 mayBegin: (Bool) -> Bool = { _ in true }) -> ShortcutResult {
        // A fresh down supersedes any key-up missed while the tap was disabled.
        if !isRepeat { captured.remove(code) }
        previousModifiers = modifiers
        let backwards = modifiers.contains(.shift)
        if hold == nil {
            // A held key must not reopen a cancelled/committed session or leak its
            // repeat events to an application that never received the initial down.
            if isRepeat { return ShortcutResult(captured.contains(code)) }
            let base = modifiers.subtracting(.shift)
            let all = code == profile.allWindows.keyCode && base == profile.allWindows.modifiers
            let current = code == profile.applicationWindows.keyCode && base == profile.applicationWindows.modifiers
            guard all || current, mayBegin(current) else { return ShortcutResult() }
            hold = all ? profile.allWindows.modifiers : profile.applicationWindows.modifiers
            cycleKey = code
            captured.insert(code)
            return ShortcutResult(true, .begin(currentApplicationOnly: current, backwards: backwards))
        }
        let command: ShortcutCommand?
        switch code {
        case 48, 50, cycleKey:
            // Shift itself moves once; the following Tab belongs to the same reverse chord.
            command = backwards && shiftAlreadyMoved ? nil : .move(backwards ? -1 : 1)
            shiftAlreadyMoved = false
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
