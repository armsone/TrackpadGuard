import AppKit
import ApplicationServices
import SwiftUI

@main
@MainActor
struct TrackpadGuardApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var appState: AppState
    @StateObject private var updateController: UpdateController
    private let settingsWindowController: SettingsWindowController

    init() {
        let settings = SettingsStore()
        let appState = AppState(settings: settings)
        let updateController = UpdateController()
        _settings = StateObject(wrappedValue: settings)
        _appState = StateObject(wrappedValue: appState)
        _updateController = StateObject(wrappedValue: updateController)
        settingsWindowController = SettingsWindowController(
            settings: settings,
            appState: appState,
            updateController: updateController
        )

        if settings.preferences.isEnabled && !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                appState.requestAccessibilityAndRetry()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Toggle("트랙패드 보호", isOn: enabledBinding)
            Text(appState.statusText)
            Divider()
            if appState.isLocked {
                Button("트랙패드 다시 켜기") { appState.unlockManually() }
            }
            Button("설정…") { settingsWindowController.show() }
                .keyboardShortcut(",")
            Button("업데이트 확인…") { updateController.checkForUpdates() }
            Button("TrackpadGuard 다시 시작") { appState.restartApplication() }
            Divider()
            Button("TrackpadGuard 종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: appState.isLocked ? MenuBarIcon.lockedImage : MenuBarIcon.image)
                .accessibilityLabel(appState.statusText)
        }
        .menuBarExtraStyle(.menu)

    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.preferences.isEnabled },
            set: { settings.preferences.isEnabled = $0 }
        )
    }
}
