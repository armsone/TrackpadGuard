import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let appState: AppState

    init(
        settings: SettingsStore,
        appState: AppState,
        updateController: UpdateController,
        appInputLanguageStore: AppInputLanguageStore
    ) {
        self.appState = appState
        let rootView = SettingsView()
            .environmentObject(settings)
            .environmentObject(appState)
            .environmentObject(updateController)
            .environmentObject(appInputLanguageStore)

        let hostingController = NSHostingController(rootView: rootView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 600)
        window.title = "InputMate 설정"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("InputMate.SettingsWindow")
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        super.init()
        window.delegate = self
    }

    func show() {
        appState.prepareForSettings()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
