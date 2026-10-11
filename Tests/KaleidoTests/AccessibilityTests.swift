import XCTest
import ApplicationServices
@testable import Kaleido

final class AccessibilityTests: XCTestCase {
    func testBatchDecodesValuesAndOmitsIndividualErrors() {
        var error = AXError.attributeUnsupported
        let unsupported = AXValueCreate(.axError, &error)!
        let attributes = [kAXTitleAttribute, kAXMinimizedAttribute, "AXFullScreen", "missing"]
        var requests = 0
        let values = Accessibility.values(AXUIElementCreateApplication(getpid()), attributes) { _, names, options, result in
            requests += 1
            XCTAssertEqual(names as? [String], attributes)
            XCTAssertEqual(options.rawValue, 0, "An unsupported optional attribute must not abort the batch")
            result.pointee = ["Fixture", true, unsupported, NSNull()] as CFArray
            return .success
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(values?[kAXTitleAttribute] as? String, "Fixture")
        XCTAssertEqual((values?[kAXMinimizedAttribute] as? NSNumber)?.boolValue, true)
        XCTAssertNil(values?["AXFullScreen"])
        XCTAssertNil(values?["missing"])
    }

    func testFailedOrIncompleteBatchIsNotAnEmptySuccessfulSnapshot() {
        let element = AXUIElementCreateApplication(getpid())
        XCTAssertNil(Accessibility.values(element, [kAXTitleAttribute]) { _, _, _, _ in .cannotComplete })
        XCTAssertNil(Accessibility.values(element, [kAXTitleAttribute]) { _, _, _, result in
            result.pointee = [] as CFArray
            return .success
        })
        XCTAssertNil(Accessibility.values(element, [kAXTitleAttribute]) { _, _, _, _ in .success })
    }

    func testEmptyTitleAndFalseStateAreRealUpdates() {
        let values = Accessibility.values(AXUIElementCreateApplication(getpid()), [kAXTitleAttribute, kAXMinimizedAttribute]) { _, _, _, result in
            result.pointee = ["", false] as CFArray
            return .success
        }
        XCTAssertEqual(values?[kAXTitleAttribute] as? String, "")
        XCTAssertEqual((values?[kAXMinimizedAttribute] as? NSNumber)?.boolValue, false)
    }

    func testUnknownWindowStateNeverTriggersAToggleWrite() {
        let element = AXUIElementCreateApplication(getpid())
        let results: [CFTypeRef?] = [nil, "invalid" as CFString]
        for result in results {
            XCTAssertFalse(Accessibility.toggle(element, kAXMinimizedAttribute, read: { _, _ in result }, write: { _, _, _ in
                XCTFail("Cannot invert an unknown state")
                return true
            }))
        }
    }

    func testToggleInvertsKnownStatesAndPropagatesWriteFailure() {
        let element = AXUIElementCreateApplication(getpid())
        for current in [false, true] {
            var writes: [Bool] = []
            let success = Accessibility.toggle(element, "AXFullScreen", read: { _, _ in NSNumber(value: current) }, write: { _, attribute, value in
                XCTAssertEqual(attribute, "AXFullScreen")
                writes.append((value as! NSNumber).boolValue)
                return false
            })
            XCTAssertFalse(success)
            XCTAssertEqual(writes, [!current])
        }
    }
}
