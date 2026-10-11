import AppKit
import ApplicationServices
import Darwin

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    // AX timeouts belong to the exact object, not its app or equal copies.
    // Apply them at the boundary so returned windows and child controls are bounded too.
    private static func prepare(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 0.2)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        prepare(element)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (value(element, attribute) as? NSNumber)?.boolValue ?? false
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    typealias CopyAttributes = (AXUIElement, CFArray, AXCopyMultipleAttributeOptions, UnsafeMutablePointer<CFArray?>) -> AXError

    /// Missing/unsupported attributes are omitted; a failed batch is not an empty snapshot.
    static func values(_ element: AXUIElement, _ attributes: [String],
                       copy: CopyAttributes = AXUIElementCopyMultipleAttributeValues) -> [String: Any]? {
        prepare(element)
        var result: CFArray?
        guard copy(element, attributes as CFArray, [], &result) == .success,
              let values = result as? [Any], values.count == attributes.count else { return nil }
        var decoded: [String: Any] = [:]
        for (attribute, value) in zip(attributes, values) {
            let type = CFGetTypeID(value as CFTypeRef)
            if type == CFNullGetTypeID() { continue }
            if type == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { continue }
            decoded[attribute] = value
        }
        return decoded
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        prepare(element)
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        prepare(element)
        return AXUIElementPerformAction(element, action as CFString) == .success
    }

    // Isolate the optional WindowServer identity bridge. AX has no public window-ID API.
    // A missing symbol falls back to CFEqual identity; it is never required for window actions.
    private typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let windowIDFunction: WindowIDFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDFunction.self)
    }()

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        prepare(element)
        var id: CGWindowID = 0
        guard windowIDFunction?(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func openSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
