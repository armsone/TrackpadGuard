import AppKit
import ApplicationServices
import Combine
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum ServiceStatus: Equatable {
        case off
        case needsAccessibility
        case ready
        case unavailable(String)
    }

    @Published private(set) var isLocked = false
    @Published private(set) var serviceStatus: ServiceStatus = .off
    @Published var transientMessage: String?

    let settings: SettingsStore

    private let eventTap = EventTapController()
    private let multitouchMonitor = MultitouchMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityPollingCancellable: AnyCancellable?

    init(settings: SettingsStore) {
        self.settings = settings

        eventTap.onKeyDown = { [weak self] _ in
            self?.lockForTyping()
        }
        eventTap.onEmergencyUnlock = { [weak self] in
            self?.unlock(reason: "긴급 해제 단축키로 트랙패드를 다시 켰습니다.")
        }
        eventTap.shouldBlock = { [weak self] type in
            self?.shouldBlock(type) ?? false
        }
        multitouchMonitor.onActivationTouch = { [weak self] in
            self?.unlock(reason: nil)
        }

        settings.$preferences
            .dropFirst()
            .sink { [weak self] preferences in
                self?.apply(preferences)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self,
                      case .needsAccessibility = self.serviceStatus,
                      self.accessibilityGranted else { return }
                self.retry()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self,
                      self.settings.preferences.isEnabled,
                      self.settings.preferences.restartProtectionAfterWake else { return }
                self.retry()
            }
            .store(in: &cancellables)

        apply(settings.preferences)
    }

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var statusText: String {
        switch serviceStatus {
        case .off: "보호 꺼짐"
        case .needsAccessibility: "손쉬운 사용 권한 필요"
        case .ready: isLocked ? "입력 중 · 트랙패드 잠김" : "보호 준비됨"
        case let .unavailable(message): message
        }
    }

    func requestAccessibilityAndRetry() {
        requestAccessibilityPermission()
        openAccessibilitySettings()
    }

    func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else {
            retry()
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startAccessibilityPolling()
    }

    func checkAccessibilityStatus() {
        refreshAccessibilityStatus()
    }

    func prepareForSettings() {
        refreshAccessibilityStatus()
        if isLocked {
            unlock(reason: nil)
        }
    }

    func retry() {
        stopServices()
        apply(settings.preferences)
    }

    func unlockManually() {
        unlock(reason: "트랙패드를 수동으로 다시 켰습니다.")
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            transientMessage = "로그인 시 실행 설정을 변경하지 못했습니다: \(error.localizedDescription)"
            if settings.preferences.launchAtLogin != (SMAppService.mainApp.status == .enabled) {
                settings.preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    func restartApplication() {
        let appPath = Bundle.main.bundlePath
        guard FileManager.default.fileExists(atPath: appPath) else {
            transientMessage = "설치된 앱 경로를 찾지 못했습니다."
            return
        }

        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "trackpadguard-relaunch", appPath]
        do {
            try relauncher.run()
            NSApp.terminate(nil)
        } catch {
            transientMessage = "앱을 다시 시작하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func apply(_ preferences: GuardPreferences) {
        multitouchMonitor.setActivationRegion(preferences.activationRegion)

        guard preferences.isEnabled else {
            stopServices()
            serviceStatus = .off
            return
        }

        guard AXIsProcessTrusted() else {
            stopServices()
            serviceStatus = .needsAccessibility
            return
        }

        do {
            try multitouchMonitor.start()
        } catch {
            stopServices()
            serviceStatus = .unavailable(error.localizedDescription)
            return
        }

        guard eventTap.start() else {
            stopServices()
            serviceStatus = .unavailable("시스템 입력 필터를 시작하지 못했습니다.")
            return
        }

        serviceStatus = .ready
    }

    private func refreshAccessibilityStatus() {
        guard settings.preferences.isEnabled else { return }

        switch (serviceStatus, AXIsProcessTrusted()) {
        case (.needsAccessibility, true):
            accessibilityPollingCancellable?.cancel()
            accessibilityPollingCancellable = nil
            retry()
        case (.ready, false):
            apply(settings.preferences)
        default:
            break
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollingCancellable?.cancel()
        let expiresAt = Date().addingTimeInterval(120)

        accessibilityPollingCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                self.refreshAccessibilityStatus()

                if self.accessibilityGranted || now >= expiresAt {
                    self.accessibilityPollingCancellable?.cancel()
                    self.accessibilityPollingCancellable = nil
                }
            }
    }

    private func stopServices() {
        isLocked = false
        eventTap.stop()
        multitouchMonitor.stop()
    }

    private func lockForTyping() {
        guard settings.preferences.isEnabled, serviceStatus == .ready else { return }
        isLocked = true
        multitouchMonitor.arm()
    }

    private func unlock(reason: String?) {
        isLocked = false
        multitouchMonitor.disarm()
        transientMessage = reason
    }

    private func shouldBlock(_ type: CGEventType) -> Bool {
        guard isLocked else { return false }

        if isPointerInput(type), !multitouchMonitor.hasActiveTouches {
            unlock(reason: nil)
            return false
        }

        let preferences = settings.preferences

        return switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            preferences.blockPointerMovement
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            preferences.blockClicks
        case .scrollWheel:
            preferences.blockScrolling
        default:
            false
        }
    }

    private func isPointerInput(_ type: CGEventType) -> Bool {
        switch type {
        case .mouseMoved,
             .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged,
             .scrollWheel, .tabletPointer, .tabletProximity:
            true
        default:
            false
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
