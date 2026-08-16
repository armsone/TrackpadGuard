# TrackpadGuard

키보드 입력이 시작되면 트랙패드의 포인터 이벤트를 잠그고, 사용자가 지정한 물리적 트랙패드 영역을 새로 터치하면 잠금을 해제하는 macOS 메뉴 막대 앱입니다.

## 기본 동작

- 키가 눌리면 트랙패드의 커서 이동, 클릭, 스크롤을 차단합니다.
- 잠금 중 트랙패드가 아닌 포인터 장치를 이동·클릭·스크롤하면 즉시 잠금을 해제합니다.
- 기본 해제 영역은 아래 두 모서리와 상단 중앙을 이은 삼각형에서 위쪽 1/3을 제거한 사다리꼴입니다.
- 설정의 **작동 영역** 탭에서 네 꼭짓점을 드래그해 영역을 변경할 수 있습니다.
- 영역 인식에 문제가 생기면 `Control-Option-Command-Escape`로 즉시 잠금을 해제할 수 있습니다.
- 설정과 작동 영역은 자동으로 저장됩니다.
- Sparkle과 GitHub Releases를 통해 서명된 자동 업데이트를 확인합니다.

## 요구 사항

- macOS 13 이상
- 내장 트랙패드가 있는 Mac
- 시스템 설정의 **개인정보 보호 및 보안 → 손쉬운 사용**에서 TrackpadGuard 허용

## 개발 빌드

프로젝트의 SwiftPM 래퍼는 캐시와 모듈 산출물을 모두 프로젝트 안에 둡니다.

```sh
./scripts/swiftpm.sh test
./scripts/package-macos.sh
```

완성된 앱과 로컬 확인용 DMG는 `dist/TrackpadGuard.app`, `dist/TrackpadGuard-local.dmg`에 생성됩니다. `CODESIGN_IDENTITY`를 지정하지 않으면 로컬 확인용 ad-hoc 서명을 사용합니다.

## 직접 배포

Developer ID 인증서로 빌드한 뒤 공증합니다.

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="notary-profile" \
./scripts/package-macos.sh --notarize
```

CCMB와 같은 릴리스 관리 흐름을 사용합니다. TrackpadGuard 전용 Sparkle 키와 인증된 GitHub CLI가 준비된 상태에서 `./scripts/publish-release.sh`를 실행하면 서명·공증된 Universal DMG, GitHub Release와 `appcast.xml`을 함께 게시합니다. 비공개 업데이트 키는 Keychain에만 저장합니다.

## 배포 제약

macOS 공개 API는 물리적 트랙패드 위의 손가락 좌표를 제공하지 않습니다. TrackpadGuard는 이 좌표를 얻기 위해 시스템의 비공개 `MultitouchSupport` 프레임워크를 런타임에 불러옵니다. 이 구현은 Mac App Store 심사 대상에 적합하지 않으며, macOS 업데이트에서 호환성을 다시 확인해야 합니다. 따라서 Developer ID 서명과 Apple 공증을 거친 직접 배포를 전제로 합니다.

트랙패드 접촉 여부를 기준으로 잠금 대상을 구분하므로, 트랙패드에 손가락을 올린 상태에서 다른 포인터 장치를 함께 조작하는 특수한 경우에는 첫 동작이 트랙패드 입력으로 간주될 수 있습니다. 시스템 프레임워크 호환성이 사라지면 앱은 트랙패드를 잠그지 않고 오류 상태를 표시하도록 실패 안전 방식으로 동작합니다.
