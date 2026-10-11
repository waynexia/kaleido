import AppKit
import KaleidoCore

if CommandLine.arguments.contains("--self-check") {
    precondition(Bundle.main.bundleIdentifier == "dev.waynexia.Kaleido", "Run from the application bundle")
    precondition(FileManager.default.isExecutableFile(atPath: Bundle.main.executablePath ?? ""))
    print("Kaleido application bundle OK")
} else if CommandLine.arguments.contains("--diagnose") {
    let result: [String: Any] = [
        "accessibilityTrusted": Accessibility.isTrusted,
        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unbundled",
        "altTabRunning": !NSRunningApplication.runningApplications(withBundleIdentifier: "com.lwouis.alt-tab-macos").isEmpty,
        "screenRecordingRequired": false,
        "shortcutProfile": UserDefaults.standard.string(forKey: "shortcutProfile") ?? "standard",
    ]
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
