import AppKit
import ApplicationServices
import SwiftUI

@main
@MainActor
struct TrackpadGuardApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var appState: AppState
    @StateObject private var updateController: UpdateController
    @StateObject private var appInputLanguageStore: AppInputLanguageStore
    private let appInputLanguageController: AppInputLanguageController
    private let settingsWindowController: SettingsWindowController

    init() {
        let settings = SettingsStore()
        let appState = AppState(settings: settings)
        let updateController = UpdateController()
        let appInputLanguageStore = AppInputLanguageStore()
        let appInputLanguageController = AppInputLanguageController(store: appInputLanguageStore)

        _settings = StateObject(wrappedValue: settings)
        _appState = StateObject(wrappedValue: appState)
        _updateController = StateObject(wrappedValue: updateController)
        _appInputLanguageStore = StateObject(wrappedValue: appInputLanguageStore)
        self.appInputLanguageController = appInputLanguageController

        settingsWindowController = SettingsWindowController(
            settings: settings,
            appState: appState,
            updateController: updateController,
            appInputLanguageStore: appInputLanguageStore
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            appState.requestAccessibilityOnFirstLaunchIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            if let message = appState.transientMessage {
                Text("⚠️ \(message)")
                    .fixedSize(horizontal: false, vertical: true)
                Button("경고 확인") { appState.transientMessage = nil }
                Divider()
            }
            Toggle("트랙패드 보호", isOn: enabledBinding)
            Text(appState.statusText)
            Toggle("앱별 언어 자동 전환", isOn: $appInputLanguageStore.isEnabled)
            Divider()
            if appState.isLocked {
                Button("트랙패드 다시 켜기") { appState.unlockManually() }
            }
            Button("설정…") { settingsWindowController.show() }
                .keyboardShortcut(",")
            Button("업데이트 확인…") { updateController.checkForUpdates() }
            Button("InputMate 다시 시작") { appState.restartApplication() }
            Divider()
            Button("InputMate 종료") { NSApplication.shared.terminate(nil) }
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
