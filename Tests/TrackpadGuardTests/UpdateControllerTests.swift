import XCTest
@testable import TrackpadGuard

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testAutomaticDownloadStatusMatchesPreference() {
        let controller = UpdateController(startingUpdater: false)

        controller.setAutomaticallyDownloadsUpdates(false)
        XCTAssertFalse(controller.automaticallyDownloadsUpdates)
        XCTAssertEqual(controller.automaticDownloadStatus, "끔 · 업데이트 확인 후 직접 다운로드합니다.")

        controller.setAutomaticallyDownloadsUpdates(true)
        XCTAssertTrue(controller.automaticallyDownloadsUpdates)
        XCTAssertEqual(controller.automaticDownloadStatus, "켬 · 새 버전을 확인하면 미리 다운로드합니다.")
    }
}
