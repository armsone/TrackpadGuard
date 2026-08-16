import SwiftUI
import TrackpadGuardCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("일반", systemImage: "switch.2") }
            regionSettings
                .tabItem { Label("작동 영역", systemImage: "square.dashed") }
            aboutView
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 640, height: 590)
    }

    private var generalSettings: some View {
        Form {
            Section {
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
                .padding(.vertical, 6)
            }

            Section("보호") {
                Toggle("키보드 입력 시 트랙패드 잠그기", isOn: enabledBinding)
                Toggle("커서 이동 차단", isOn: preferenceBinding(\.blockPointerMovement))
                Toggle("클릭 차단", isOn: preferenceBinding(\.blockClicks))
                Toggle("스크롤 차단", isOn: preferenceBinding(\.blockScrolling))
                if appState.isLocked {
                    Button("지금 트랙패드 다시 켜기") { appState.unlockManually() }
                }
            }

            Section("시작") {
                Toggle("로그인 시 자동 실행", isOn: launchAtLoginBinding)
            }

            Section("긴급 해제") {
                LabeledContent("단축키", value: "⌃⌥⌘ Esc")
                Text("설정한 영역을 인식하지 못하는 경우에도 이 단축키로 즉시 잠금을 해제할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var regionSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("트랙패드를 다시 켤 영역")
                .font(.title2.bold())
            Text("초록색 꼭짓점을 드래그하세요. 기본값은 중앙 삼각형의 상단 1/3을 제거한 사다리꼴입니다.")
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
        .padding(.horizontal, 6)
    }

    private var aboutView: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.raised.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("TrackpadGuard")
                .font(.largeTitle.bold())
            Text("키보드 입력 중 의도하지 않은 트랙패드 조작을 막습니다.")
                .foregroundStyle(.secondary)
            GroupBox("배포 안내") {
                Text("물리적 트랙패드 접촉 좌표를 얻기 위해 macOS의 비공개 MultitouchSupport 프레임워크를 동적으로 사용합니다. 따라서 Mac App Store가 아닌 Developer ID 서명 및 공증 방식으로 배포해야 합니다.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            Spacer()
            Text("버전 0.1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
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
        case .off: "입력 이벤트를 감시하지 않습니다."
        case .needsAccessibility: "입력을 감지하고 차단하려면 시스템 권한이 필요합니다."
        case .ready: appState.isLocked ? "설정한 초록색 영역을 터치하면 해제됩니다." : "다음 키 입력부터 트랙패드를 잠급니다."
        case .unavailable: "보호 기능을 시작하지 못했습니다."
        }
    }
}
