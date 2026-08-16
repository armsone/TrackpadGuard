import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let appState: AppState

    init(settings: SettingsStore, appState: AppState, updateController: UpdateController) {
        self.appState = appState
        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(appState)
            .environmentObject(updateController)

        let hostingController = NSHostingController(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TrackpadGuard 설정"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TrackpadGuard.SettingsWindow")
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        super.init()
        window.delegate = self
    }

    func show() {
        appState.checkAccessibilityStatus()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
