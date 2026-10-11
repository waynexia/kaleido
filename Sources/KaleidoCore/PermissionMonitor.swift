/// Checks once at startup, then only while waiting for permission. All callbacks
/// must run on the same executor; the application supplies its main-run-loop timer.
public final class PermissionMonitor {
    public typealias Schedule = (@escaping () -> Void) -> (() -> Void)

    private let check: () -> Bool
    private let schedule: Schedule
    private var cancelPolling: (() -> Void)?
    private var started = false
    private var hasChecked = false
    public private(set) var isTrusted = false
    public var onChange: ((Bool) -> Void)?

    public init(check: @escaping () -> Bool, schedule: @escaping Schedule) {
        self.check = check
        self.schedule = schedule
    }

    public func start() {
        guard !started else { return }
        started = true
        checkIfNeeded()
    }

    public func checkIfNeeded() {
        guard started, !isTrusted else { return }
        let trusted = check()
        let changed = !hasChecked || trusted != isTrusted
        hasChecked = true
        isTrusted = trusted
        if trusted {
            cancelPolling?()
            cancelPolling = nil
        } else if cancelPolling == nil {
            cancelPolling = schedule { [weak self] in self?.checkIfNeeded() }
        }
        if changed { onChange?(trusted) }
    }

    public func stop() {
        started = false
        cancelPolling?()
        cancelPolling = nil
    }

    deinit { cancelPolling?() }
}
