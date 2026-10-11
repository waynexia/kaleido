import XCTest
@testable import KaleidoCore

final class PermissionMonitorTests: XCTestCase {
    private final class Environment {
        var trusted = false
        var queryCount = 0
        var scheduleCount = 0
        var cancellationCount = 0
        var tick: (() -> Void)?

        func makeMonitor() -> PermissionMonitor {
            PermissionMonitor(check: {
                self.queryCount += 1
                return self.trusted
            }, schedule: { tick in
                self.scheduleCount += 1
                self.tick = tick
                return { self.cancellationCount += 1 }
            })
        }
    }

    func testAlreadyAuthorizedLaunchChecksOnceWithoutScheduling() {
        let environment = Environment()
        environment.trusted = true
        let monitor = environment.makeMonitor()
        var states: [Bool] = []
        monitor.onChange = { states.append($0) }
        monitor.start()
        monitor.start()
        monitor.checkIfNeeded()
        XCTAssertEqual(states, [true])
        XCTAssertEqual(environment.queryCount, 1)
        XCTAssertEqual(environment.scheduleCount, 0)
    }

    func testGrantAutomaticallyConfirmsAndCancelsPolling() {
        let environment = Environment()
        let monitor = environment.makeMonitor()
        var states: [Bool] = []
        monitor.onChange = { states.append($0) }
        monitor.start()
        environment.tick?()
        XCTAssertEqual(states, [false])
        XCTAssertEqual(environment.scheduleCount, 1)
        XCTAssertEqual(environment.cancellationCount, 0)

        environment.trusted = true
        environment.tick?()
        XCTAssertTrue(monitor.isTrusted)
        XCTAssertEqual(states, [false, true])
        XCTAssertEqual(environment.queryCount, 3)
        XCTAssertEqual(environment.cancellationCount, 1)

        // Even an already-enqueued timer callback or another activation cannot
        // query permission again once authorization has been confirmed.
        environment.tick?()
        monitor.checkIfNeeded()
        monitor.start()
        XCTAssertEqual(environment.queryCount, 3)
        XCTAssertEqual(environment.scheduleCount, 1)
    }

    func testReturnFromSettingsCanConfirmBeforeNextTimerTick() {
        let environment = Environment()
        let monitor = environment.makeMonitor()
        monitor.start()
        environment.trusted = true
        monitor.checkIfNeeded()
        XCTAssertTrue(monitor.isTrusted)
        XCTAssertEqual(environment.queryCount, 2)
        XCTAssertEqual(environment.cancellationCount, 1)
    }

    func testStoppingWhileWaitingCancelsAndIgnoresQueuedTicks() {
        let environment = Environment()
        let monitor = environment.makeMonitor()
        monitor.start()
        monitor.stop()
        environment.tick?()
        monitor.checkIfNeeded()
        XCTAssertEqual(environment.queryCount, 1)
        XCTAssertEqual(environment.cancellationCount, 1)
        XCTAssertFalse(monitor.isTrusted)
    }
}
