import XCTest
@testable import TrackpadGuardCore

final class ActivationRegionTests: XCTestCase {
    func testDefaultRegionMatchesRequestedTrapezoid() {
        let region = ActivationRegion.default

        XCTAssertEqual(region.bottomLeft, .init(x: 0, y: 0))
        XCTAssertEqual(region.bottomRight, .init(x: 1, y: 0))
        XCTAssertEqual(region.topLeft.x, 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(region.topRight.x, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(region.topLeft.y, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(region.topRight.y, 2.0 / 3.0, accuracy: 0.000_001)
    }

    func testDefaultRegionContainsLowerCenterButNotRemovedUpperThird() {
        let region = ActivationRegion.default

        XCTAssertTrue(region.contains(.init(x: 0.5, y: 0.3)))
        XCTAssertTrue(region.contains(.init(x: 0.5, y: 2.0 / 3.0)))
        XCTAssertFalse(region.contains(.init(x: 0.5, y: 0.85)))
        XCTAssertFalse(region.contains(.init(x: 0.05, y: 0.8)))
    }

    func testUpdatingVertexClampsToTrackpadAndKeepsMinimumGap() {
        let region = ActivationRegion.default
        let updated = region.updating(.topLeft, to: .init(x: 0.99, y: 1.4))

        XCTAssertEqual(updated.topLeft.y, 1)
        XCTAssertLessThanOrEqual(updated.topLeft.x, updated.topRight.x - 0.04)
    }

    func testPreferencesRegionRoundTripsThroughJSON() throws {
        let encoded = try JSONEncoder().encode(ActivationRegion.default)
        let decoded = try JSONDecoder().decode(ActivationRegion.self, from: encoded)
        XCTAssertEqual(decoded, .default)
    }
}
