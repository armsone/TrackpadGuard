import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var automaticallyDownloadsUpdates = false

    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = enabled
    }

    var automaticDownloadStatus: String {
        automaticallyDownloadsUpdates
            ? "켬 · 새 버전을 확인하면 미리 다운로드합니다."
            : "끔 · 업데이트 확인 후 직접 다운로드합니다."
    }
}
