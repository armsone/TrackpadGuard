import Combine
import XCTest
@testable import TrackpadGuard

@MainActor
final class AppStateTests: XCTestCase {
    /// 보호 기능을 끈 상태로 만들어 이벤트 탭·멀티터치 감시 없이 AppState를 생성한다.
    private func makeDisabledAppState(defaults: UserDefaults) -> AppState {
        let settings = SettingsStore(defaults: defaults)
        settings.preferences.isEnabled = false
        return AppState(settings: settings)
    }

    func testUnlockDoesNotPublishWhenNothingChanges() throws {
        let suiteName = "TrackpadGuard.AppStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = makeDisabledAppState(defaults: defaults)
        var publishCount = 0
        let cancellable = appState.objectWillChange.sink { publishCount += 1 }
        defer { cancellable.cancel() }

        XCTAssertFalse(appState.isLocked)
        XCTAssertNil(appState.transientMessage)

        // 잠기지 않은 상태에서 잠금 해제: isLocked(false→false)와 transientMessage(nil→nil)는 변경이 없어야 한다.
        appState.prepareForSettings()
        XCTAssertEqual(publishCount, 0)

        // 수동 해제는 메시지가 바뀌므로 정확히 한 번만 알린다(isLocked는 그대로).
        appState.unlockManually()
        XCTAssertEqual(publishCount, 1)
        XCTAssertNotNil(appState.transientMessage)

        // 같은 메시지로 다시 해제하면 아무것도 바뀌지 않으므로 추가 알림이 없어야 한다.
        appState.unlockManually()
        XCTAssertEqual(publishCount, 1)
    }
}
