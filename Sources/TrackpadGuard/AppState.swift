import AppKit
import ApplicationServices
import Combine
import OSLog
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
    private let typoCorrector = KoreanTypoCorrector()
    private let multitouchMonitor = MultitouchMonitor()
    private let healthMonitor = ProcessHealthMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityPollingCancellable: AnyCancellable?
    private var automaticUnlockTask: Task<Void, Never>?
    private var lastAutomaticServiceRecoveryAt: Date?
    private var periodicRelaunchTimer: Timer?

    private let periodicRelaunchInterval: TimeInterval = 30 * 60
    private let automaticRelaunchDateKey = "TrackpadGuard.lastAutomaticRelaunchDate"
    private let serviceRecoveryEscalationInterval: TimeInterval = 10 * 60
    private let automaticRelaunchCooldown: TimeInterval = 30 * 60
    private let healthLogger = Logger(subsystem: "com.nasfinder.TrackpadGuard", category: "Health")

    init(settings: SettingsStore) {
        self.settings = settings

        eventTap.onKeyDown = { [weak self] event in
            self?.lockForTyping()
            return self?.typoCorrector.handleKeyDown(event) ?? false
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
        healthMonitor.onIssue = { [weak self] issue, snapshot in
            self?.recoverFromHealthIssue(issue, snapshot: snapshot)
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
        startPeriodicRelaunchTimer()
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
        _ = relaunchApplication(failureMessage: "앱을 다시 시작하지 못했습니다")
    }

    @discardableResult
    private func relaunchApplication(failureMessage: String?) -> Bool {
        let appPath = Bundle.main.bundlePath
        guard FileManager.default.fileExists(atPath: appPath) else {
            transientMessage = "설치된 앱 경로를 찾지 못했습니다."
            return false
        }

        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "trackpadguard-relaunch", appPath]
        do {
            try relauncher.run()
            NSApp.terminate(nil)
            return true
        } catch {
            if let failureMessage {
                transientMessage = "\(failureMessage): \(error.localizedDescription)"
            }
            return false
        }
    }

    private func apply(_ preferences: GuardPreferences) {
        multitouchMonitor.setActivationRegion(preferences.activationRegion)
        typoCorrector.isEnabled = preferences.correctKoreanTypos
        typoCorrector.prefersKorean = preferences.preferKoreanTypoCorrection

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
        if preferences.automaticallyRecoverFromHighLoad {
            healthMonitor.start()
        } else {
            healthMonitor.stop()
        }
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
        typoCorrector.reset()
        healthMonitor.stop()
        automaticUnlockTask?.cancel()
        automaticUnlockTask = nil
        setLocked(false)
        eventTap.stop()
        multitouchMonitor.stop()
    }

    private func recoverFromHealthIssue(_ issue: ProcessHealthIssue, snapshot: ProcessHealthSnapshot) {
        guard settings.preferences.isEnabled,
              settings.preferences.automaticallyRecoverFromHighLoad else {
            healthMonitor.stop()
            return
        }

        let now = Date()
        let memoryMB = Double(snapshot.residentBytes) / 1_024 / 1_024
        healthLogger.warning(
            "Automatic recovery requested: \(issue.recoveryDescription, privacy: .public), CPU \(snapshot.cpuPercent, format: .fixed(precision: 1))%, memory \(memoryMB, format: .fixed(precision: 1)) MB, main delay \(snapshot.mainThreadDelay, format: .fixed(precision: 1)) seconds"
        )
        if let lastRecovery = lastAutomaticServiceRecoveryAt,
           now.timeIntervalSince(lastRecovery) <= serviceRecoveryEscalationInterval,
           canAutomaticallyRelaunch(at: now) {
            if relaunchApplication(failureMessage: "자동으로 앱을 다시 시작하지 못했습니다") {
                UserDefaults.standard.set(now, forKey: automaticRelaunchDateKey)
                return
            }
        }

        lastAutomaticServiceRecoveryAt = now
        retry()
        transientMessage = "\(issue.recoveryDescription)을 감지해 보호 기능을 자동으로 복구했습니다."
    }

    // 장시간 실행 시 키 입력 누락을 완화하기 위해 30분마다 새 인스턴스를 띄우고 종료한다.
    // relaunchApplication은 새 인스턴스 실행에 성공했을 때만 기존 인스턴스를 종료하며,
    // 실패하면 타이머가 유지되어 다음 주기에 다시 시도한다.
    private func startPeriodicRelaunchTimer() {
        periodicRelaunchTimer?.invalidate()
        let timer = Timer(timeInterval: periodicRelaunchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performPeriodicRelaunch() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        periodicRelaunchTimer = timer
    }

    private func performPeriodicRelaunch() {
        if relaunchApplication(failureMessage: nil) {
            periodicRelaunchTimer?.invalidate()
            periodicRelaunchTimer = nil
        }
    }

    private func canAutomaticallyRelaunch(at date: Date) -> Bool {
        guard let previous = UserDefaults.standard.object(forKey: automaticRelaunchDateKey) as? Date else {
            return true
        }
        return date.timeIntervalSince(previous) >= automaticRelaunchCooldown
    }

    // @Published는 같은 값을 다시 대입해도 알림을 보내므로 실제 전환만 발행한다.
    private func lockForTyping() {
        guard settings.preferences.isEnabled, serviceStatus == .ready else { return }
        setLocked(true)
        multitouchMonitor.arm()
        scheduleAutomaticUnlock()
    }

    private func unlock(reason: String?) {
        automaticUnlockTask?.cancel()
        automaticUnlockTask = nil
        setLocked(false)
        multitouchMonitor.disarm()
        if transientMessage != reason {
            transientMessage = reason
        }
    }

    private func setLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
    }

    private func scheduleAutomaticUnlock() {
        automaticUnlockTask?.cancel()
        automaticUnlockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.unlock(reason: nil)
        }
    }

    private func shouldBlock(_ type: CGEventType) -> Bool {
        // 클릭으로 커서 위치가 바뀌면 교정 후보 구절이 무효가 되므로 비운다.
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            typoCorrector.reset()
        default:
            break
        }

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
