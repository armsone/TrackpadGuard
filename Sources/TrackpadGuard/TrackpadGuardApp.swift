import AppKit
import ApplicationServices
import SwiftUI

@main
@MainActor
struct TrackpadGuardApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var appState: AppState
    @StateObject private var updateController = UpdateController()

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _appState = StateObject(wrappedValue: AppState(settings: settings))

        if settings.preferences.isEnabled && !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
            Button("설정…") { openSettings() }
                .keyboardShortcut(",")
            Button("업데이트 확인…") { updateController.checkForUpdates() }
            Divider()
            Button("TrackpadGuard 종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: appState.isLocked ? "hand.raised.fill" : "hand.raised")
                .accessibilityLabel(appState.statusText)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(appState)
                .alert(
                    "TrackpadGuard",
                    isPresented: Binding(
                        get: { appState.transientMessage != nil },
                        set: { if !$0 { appState.transientMessage = nil } }
                    )
                ) {
                    Button("확인") { appState.transientMessage = nil }
                } message: {
                    Text(appState.transientMessage ?? "")
                }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.preferences.isEnabled },
            set: { settings.preferences.isEnabled = $0 }
        )
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
