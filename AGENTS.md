# TrackpadGuard 프로젝트 규칙

관련 작업은 전체 규칙 `/Users/armsone/git/AGENTS.md`를 먼저 읽고 이 파일을 프로젝트 규칙으로 적용한다. 같은 대화에서는 규칙이 변경되거나 새 저장소로 작업 범위가 넓어질 때만 다시 읽는다.

- SwiftPM 명령은 반드시 `./scripts/swiftpm.sh` 래퍼로 실행한다.
- 로컬 Universal 앱 번들은 `./scripts/build-app.sh`, 로컬 DMG는 `./scripts/package-macos.sh`로 만든다.
- 외부 릴리스는 `Resources/Info.plist`의 버전과 빌드를 올리고 테스트를 통과한 뒤 `./scripts/publish-release.sh`로 수행한다.
- `MultitouchMonitor.swift`의 구조체 레이아웃과 비공개 함수 시그니처는 실기기 검증 없이 변경하지 않는다.
- Sparkle 비공개 키, Apple 인증서, 공증 자격증명과 생성된 `dist/` 산출물은 커밋하지 않는다.
