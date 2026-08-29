import XCTest
@testable import TrackpadGuard

final class ProcessHealthMonitorTests: XCTestCase {
    func testExistingPreferencesEnableAutomaticRecoveryByDefault() throws {
        let preferences = try JSONDecoder().decode(GuardPreferences.self, from: Data("{}".utf8))

        XCTAssertTrue(preferences.automaticallyRecoverFromHighLoad)
    }

    func testBriefCPUAndMemorySpikeDoesNotTriggerRecovery() {
        var evaluator = ProcessHealthEvaluator()

        for _ in 0..<5 {
            XCTAssertNil(evaluator.evaluate(snapshot(cpu: 80, memoryMB: 300)))
        }
        XCTAssertNil(evaluator.evaluate(snapshot(cpu: 0, memoryMB: 40)))
    }

    func testSustainedCPUTriggersRecoveryAfterSixSamples() {
        var evaluator = ProcessHealthEvaluator()

        for _ in 0..<5 {
            XCTAssertNil(evaluator.evaluate(snapshot(cpu: 80)))
        }
        XCTAssertEqual(evaluator.evaluate(snapshot(cpu: 80)), .sustainedCPU)
    }

    func testSustainedMemoryTriggersRecoveryAfterSixSamples() {
        var evaluator = ProcessHealthEvaluator()

        for _ in 0..<5 {
            XCTAssertNil(evaluator.evaluate(snapshot(memoryMB: 300)))
        }
        XCTAssertEqual(evaluator.evaluate(snapshot(memoryMB: 300)), .excessiveMemory)
    }

    func testMainThreadMustBeDelayedTwice() {
        var evaluator = ProcessHealthEvaluator()

        XCTAssertNil(evaluator.evaluate(snapshot(mainThreadDelay: 16)))
        XCTAssertEqual(evaluator.evaluate(snapshot(mainThreadDelay: 21)), .unresponsiveMainThread)
    }

    func testHealthySampleResetsConsecutiveCount() {
        var evaluator = ProcessHealthEvaluator()

        for _ in 0..<4 {
            XCTAssertNil(evaluator.evaluate(snapshot(cpu: 80)))
        }
        XCTAssertNil(evaluator.evaluate(snapshot(cpu: 0)))
        for _ in 0..<5 {
            XCTAssertNil(evaluator.evaluate(snapshot(cpu: 80)))
        }
    }

    private func snapshot(
        cpu: Double = 0,
        memoryMB: UInt64 = 40,
        mainThreadDelay: TimeInterval = 0
    ) -> ProcessHealthSnapshot {
        ProcessHealthSnapshot(
            cpuPercent: cpu,
            residentBytes: memoryMB * 1_024 * 1_024,
            mainThreadDelay: mainThreadDelay
        )
    }
}
