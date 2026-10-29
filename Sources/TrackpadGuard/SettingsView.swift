import SwiftUI
import TrackpadGuardCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var updateController: UpdateController
    @EnvironmentObject private var appInputLanguageStore: AppInputLanguageStore

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 8) {
            if let message = appState.transientMessage {
                warningBanner(message)
            }
            TabView(selection: $selectedTab) {
                AppInputLanguageSettingsView()
                    .tabItem { Label("앱별 입력 언어", systemImage: "globe") }
                    .tag(0)

                koreanTypoSettings
                    .tabItem { Label("한글 교정", systemImage: "character.textbox") }
                    .tag(1)

                trackpadSettings
                    .tabItem { Label("트랙패드", systemImage: "hand.raised") }
                    .tag(2)

                generalAndAboutSettings
                    .tabItem { Label("일반 / 정보", systemImage: "gearshape") }
                    .tag(3)
            }
        }
        .padding(16)
        .frame(minWidth: 740, minHeight: 580)
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("확인") { appState.transientMessage = nil }
                .accessibilityLabel("경고 확인 및 닫기")
        }
        .padding(10)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Tab 2: 한글 교정

    private var koreanTypoSettings: some View {
        ScrollView {
            Form {
                Section("한글 자동 교정") {
                    Toggle("영문 자판으로 잘못 쓴 한글 자동 교정", isOn: preferenceBinding(\.correctKoreanTypos))
                    Toggle("한글 우선 변환 (영어를 거의 쓰지 않을 때)", isOn: preferenceBinding(\.preferKoreanTypoCorrection))
                        .disabled(!settings.preferences.correctKoreanTypos)
                    Toggle("입력 중 실시간 한영 자동 전환", isOn: preferenceBinding(\.continuousLanguageSwitching))
                        .disabled(!settings.preferences.correctKoreanTypos)
                    Toggle("영문+한글 혼용 보정 및 한글 자판 영문 복원", isOn: preferenceBinding(\.correctMixedAndRestoreEnglish))
                        .disabled(!settings.preferences.correctKoreanTypos)

                    Text("영문 자판으로 친 한글(dkssud → 안녕)을 공백이나 문장 부호 입력 시점에 자동 교정하며, AI로·deploy했는데 같은 혼용 단어를 문맥에 맞게 보정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("자세한 동작 원리 및 주의사항") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• ABC·US 영문 자판에서는 공백 없이 치는 도중에 dkssud를 안녕으로 바꾸며, 빈 입력창의 첫 단어부터 동작합니다.")
                            Text("• 한글 2벌식 자판에서는 첫 자음이 중복되지 않도록 macOS 입력기가 글자를 조합하고, hello처럼 한글로 조합되지 않는 영어는 공백 등으로 입력을 확정한 뒤 교정합니다.")
                            Text("• 전환 직후 Delete는 되돌리기이며, 실시간 전환이 동작하는 입력창에서는 '' 강제 변환을 쓰지 않습니다.")
                            Text("• git(햣)·did(양)처럼 완성된 한글로도 조합되는 단어는 한글로 남으니 직접 입력 소스를 바꿔 주세요.")
                            Text("• 글자 교체 결과를 즉시 확인할 수 없는 앱(일부 브라우저·Electron 앱), 터미널, ABC·US·한글 2벌식 외 자판에서는 구분자 기반 교정만 쓰고, 암호·보안 입력 중에는 아무것도 하지 않습니다.")
                            Text("• 교체 중 커서를 되돌렸는지 확인하지 못하면 원문이 지워지지 않도록 그 키를 입력하지 않고 안내합니다.")
                            Text("• 기본 모드는 영어일 가능성이 낮은 두 단어 이상의 문장만 자동 변환합니다. 한글 우선 변환을 켜면 영문 자판으로 조합 가능한 두 단어 이상을 대부분 한글로 바꿉니다. 한 단어나 자동 교정되지 않는 글은 끝에 ''를 입력하면 강제로 바꿉니다.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    }
                }

                Section("첫 단어 입력 복구") {
                    Toggle("선택한 앱에서 빈 입력창 첫 단어 복구", isOn: preferenceBinding(\.firstWordRecoveryEnabled))
                    Text("선택한 앱의 빈 입력창에서 첫 단어를 입력할 때 실시간 입력 화면을 그대로 유지하며, 공백이나 문장 부호 입력 시점에 조합 의도와 실제 입력 결과를 비교해 안전한 경우에만 자동으로 교정합니다. 지원되지 않거나 불확실한 입력창은 건너뜁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settings.preferences.firstWordRecoveryBundleIDs.isEmpty {
                        Text("선택된 앱이 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.preferences.firstWordRecoveryBundleIDs, id: \.self) { bundleID in
                            HStack {
                                Text(displayName(for: bundleID))
                                Spacer()
                                Button(role: .destructive) {
                                    removeFirstWordRecoveryApp(bundleID)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(displayName(for: bundleID)) 삭제")
                            }
                        }
                    }

                    Button("앱 추가…") {
                        selectAppForFirstWordRecovery()
                    }
                    .disabled(!settings.preferences.firstWordRecoveryEnabled)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Tab 3: 트랙패드

    private var trackpadSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 상태 안내 헤더
                HStack(spacing: 12) {
                    Image(systemName: statusSymbol)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.statusText).font(.headline)
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .needsAccessibility = appState.serviceStatus {
                        Button("권한 설정 열기") { appState.requestAccessibilityAndRetry() }
                    } else if case .unavailable = appState.serviceStatus {
                        Button("다시 시도") { appState.retry() }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                Form {
                    Section("트랙패드 잠금 보호") {
                        Toggle("키보드 입력 시 트랙패드 잠그기", isOn: enabledBinding)
                        Toggle("커서 이동 차단", isOn: preferenceBinding(\.blockPointerMovement))
                        Toggle("클릭 차단", isOn: preferenceBinding(\.blockClicks))
                        Toggle("스크롤 차단", isOn: preferenceBinding(\.blockScrolling))
                        if appState.isLocked {
                            Button("지금 트랙패드 다시 켜기") { appState.unlockManually() }
                        }
                    }

                    Section("긴급 해제") {
                        LabeledContent("단축키", value: "⌃⌥⌘ Esc")
                        Text("트랙패드가 아닌 마우스 등 외부 포인터 장치를 조작하거나 위 단축키를 누르면 즉시 잠금이 해제됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                VStack(alignment: .leading, spacing: 10) {
                    Text("트랙패드를 다시 켤 작동 영역")
                        .font(.headline)
                    Text("초록색 꼭짓점이나 그 근처를 드래그하세요. 기본값은 중앙 사다리꼴 영역입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    RegionEditorView(region: regionBinding)

                    HStack {
                        Label("좌표는 트랙패드 크기에 맞춰 비율로 저장됩니다.", systemImage: "ruler")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("기본값으로 복원") { settings.resetActivationRegion() }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
        }
    }

    // MARK: - Tab 4: 일반 / 정보

    private var generalAndAboutSettings: some View {
        ScrollView {
            VStack(spacing: 16) {
                Form {
                    Section("시작 및 복구") {
                        Toggle("Mac 재시작·로그인 후 자동 실행", isOn: launchAtLoginBinding)
                        Toggle("잠자기에서 깨어날 때 보호 기능 다시 시작", isOn: preferenceBinding(\.restartProtectionAfterWake))
                        Toggle("부하가 계속되면 자동으로 복구", isOn: preferenceBinding(\.automaticallyRecoverFromHighLoad))
                        Button("InputMate 다시 시작") { appState.restartApplication() }
                    }

                    Section("업데이트") {
                        Button("업데이트 수동 확인…") { updateController.checkForUpdates() }
                        Toggle(
                            "업데이트 자동 다운로드",
                            isOn: Binding(
                                get: { updateController.automaticallyDownloadsUpdates },
                                set: { updateController.setAutomaticallyDownloadsUpdates($0) }
                            )
                        )
                        Text(updateController.automaticDownloadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                VStack(spacing: 12) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("InputMate")
                        .font(.title.bold())
                    Text("키보드와 트랙패드를 편하게")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    GroupBox("배포 및 호환성 안내") {
                        Text("물리적 트랙패드 접촉 좌표를 얻기 위해 macOS의 MultitouchSupport 프레임워크를 사용합니다. Apple 공증 및 Developer ID 서명 방식으로 직접 배포됩니다.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                            .font(.caption)
                    }

                    GroupBox("만든이") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("한병기")
                                    .font(.subheadline.bold())
                                Text("GitHub · armsone")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("GitHub 저장소…", destination: URL(string: "https://github.com/armsone/TrackpadGuard")!)
                        }
                        .padding(4)
                    }

                    Text("버전 \(appVersion) (\(buildStamp))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
        }
    }

    // MARK: - Properties and Bindings

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.4.0"
    }

    private var buildStamp: String {
        Bundle.main.object(forInfoDictionaryKey: "BuildStamp") as? String ?? "202610291358"
    }

    private var enabledBinding: Binding<Bool> {
        preferenceBinding(\.isEnabled)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.preferences.launchAtLogin },
            set: { value in
                settings.preferences.launchAtLogin = value
                appState.updateLaunchAtLogin(value)
            }
        )
    }

    private var regionBinding: Binding<ActivationRegion> {
        Binding(
            get: { settings.preferences.activationRegion },
            set: { settings.preferences.activationRegion = $0 }
        )
    }

    private func preferenceBinding(_ keyPath: WritableKeyPath<GuardPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { settings.preferences[keyPath: keyPath] = $0 }
        )
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            if let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) {
                return name
            }
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private func selectAppForFirstWordRecovery() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.prompt = "선택"
        if panel.runModal() == .OK,
           let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleID = bundle.bundleIdentifier {
            if !settings.preferences.firstWordRecoveryBundleIDs.contains(bundleID) {
                settings.preferences.firstWordRecoveryBundleIDs.append(bundleID)
            }
        }
    }

    private func removeFirstWordRecoveryApp(_ bundleID: String) {
        settings.preferences.firstWordRecoveryBundleIDs.removeAll { $0 == bundleID }
    }

    private var statusSymbol: String {
        switch appState.serviceStatus {
        case .off: "pause.circle.fill"
        case .needsAccessibility: "exclamationmark.shield.fill"
        case .ready: appState.isLocked ? "hand.raised.fill" : "checkmark.shield.fill"
        case .unavailable: "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch appState.serviceStatus {
        case .ready: appState.isLocked ? .orange : .green
        case .off: .secondary
        case .needsAccessibility: .orange
        case .unavailable: .red
        }
    }

    private var statusDescription: String {
        switch appState.serviceStatus {
        case .off: "트랙패드 입력 이벤트를 감시하지 않습니다."
        case .needsAccessibility: "트랙패드 제어 및 입력 감지에 손쉬운 사용 권한이 필요합니다."
        case .ready: appState.isLocked ? "키보드 입력으로 트랙패드가 잠겼습니다. 설정 영역 터치 시 해제됩니다." : "키보드 입력이 시작되면 트랙패드를 자동으로 잠급니다."
        case .unavailable: "보호 서비스를 시작하지 못했습니다."
        }
    }
}
