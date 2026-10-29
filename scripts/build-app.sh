#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/InputMate.app"
CONTENTS_DIR="$APP_DIR/Contents"
CONFIGURATION=${CONFIGURATION:-release}
ARCHS=${ARCHS:-"arm64 x86_64"}
BUILD_ROOT="$PROJECT_DIR/.build/distribution"

# 손쉬운 사용 같은 시스템 권한은 코드 서명의 지정 요구사항(DR)에 묶인다. ad-hoc 서명은 빌드마다 DR(cdhash)이 달라
# 권한이 매번 다시 요청되므로, 인증서가 없을 때 조용히 ad-hoc으로 내려가지 않고 명확히 실패한다.
# 로컬 확인용 ad-hoc 빌드가 정말 필요하면 TRACKPADGUARD_ALLOW_ADHOC_SIGNING=1을 명시한다.
DEFAULT_DEVELOPER_ID="Developer ID Application: BYOUNG KI HAN (T7B4EPLHPK)"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$CODESIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$DEFAULT_DEVELOPER_ID\""; then
  SIGNING_IDENTITY="$DEFAULT_DEVELOPER_ID"
else
  echo "서명 인증서를 찾지 못했습니다: $DEFAULT_DEVELOPER_ID" >&2
  echo "키체인 접근이 막힌 환경이거나 인증서가 없는 경우입니다. 이 상태로 ad-hoc 빌드를 만들면 시스템 권한이 유지되지 않으므로 중단합니다." >&2
  echo "CODESIGN_IDENTITY로 인증서를 지정하거나, 권한 유지가 필요 없는 로컬 확인용이면 TRACKPADGUARD_ALLOW_ADHOC_SIGNING=1을 설정하세요." >&2
  SIGNING_IDENTITY=""
fi
if [[ "$SIGNING_IDENTITY" == "-" || -z "$SIGNING_IDENTITY" ]]; then
  if [[ "${TRACKPADGUARD_ALLOW_ADHOC_SIGNING:-}" != "1" ]]; then
    [[ -n "$SIGNING_IDENTITY" ]] && echo "ad-hoc 서명(-)은 TRACKPADGUARD_ALLOW_ADHOC_SIGNING=1일 때만 허용됩니다." >&2
    exit 78
  fi
  SIGNING_IDENTITY="-"
  echo "경고: ad-hoc 서명입니다. 설치하면 손쉬운 사용 권한을 다시 승인해야 합니다." >&2
fi

typeset -a ARCH_LIST
typeset -a BINARY_PATHS
ARCH_LIST=(${=ARCHS})

for ARCH in $ARCH_LIST; do
  SCRATCH_PATH="$BUILD_ROOT/$ARCH"
  TARGET_TRIPLE="$ARCH-apple-macosx13.0"
  "$SCRIPT_DIR/swiftpm.sh" build \
    --scratch-path "$SCRATCH_PATH" \
    --triple "$TARGET_TRIPLE" \
    -c "$CONFIGURATION" \
    --product TrackpadGuard
  BIN_DIR=$("$SCRIPT_DIR/swiftpm.sh" build \
    --scratch-path "$SCRATCH_PATH" \
    --triple "$TARGET_TRIPLE" \
    -c "$CONFIGURATION" \
    --show-bin-path)
  BINARY_PATHS+=("$BIN_DIR/TrackpadGuard")
done

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
if (( ${#BINARY_PATHS[@]} == 1 )); then
  cp "$BINARY_PATHS[1]" "$CONTENTS_DIR/MacOS/TrackpadGuard"
else
  xcrun lipo -create $BINARY_PATHS -output "$CONTENTS_DIR/MacOS/TrackpadGuard"
fi
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if [[ -d "$PROJECT_DIR/Resources/Assets.xcassets" ]]; then
  xcrun actool "$PROJECT_DIR/Resources/Assets.xcassets" \
    --compile "$CONTENTS_DIR/Resources" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$PROJECT_DIR/.build/asset-info.plist"
fi

SPARKLE_FRAMEWORK_SOURCE="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "Sparkle.framework을 찾을 수 없습니다: $SPARKLE_FRAMEWORK_SOURCE" >&2
  exit 66
fi
mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
rm -rf "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$CONTENTS_DIR/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS_DIR/MacOS/TrackpadGuard"

SPARKLE_PUBLIC_KEY_FILE="$PROJECT_DIR/Configuration/SparklePublicKey.txt"
if [[ -f "$SPARKLE_PUBLIC_KEY_FILE" ]]; then
  SPARKLE_PUBLIC_KEY=$(tr -d '\r\n' < "$SPARKLE_PUBLIC_KEY_FILE")
  if [[ ! "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Sparkle 공개 키 형식이 올바르지 않습니다." >&2
    exit 65
  fi
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"
fi

SIGN_OPTIONS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGN_OPTIONS+=(--options runtime --timestamp)
fi
codesign $SIGN_OPTIONS "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign $SIGN_OPTIONS "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign $SIGN_OPTIONS "$CONTENTS_DIR/Frameworks/Sparkle.framework"
codesign $SIGN_OPTIONS \
  --entitlements "$PROJECT_DIR/Resources/TrackpadGuard.entitlements" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
codesign -d -r- "$APP_DIR" 2>&1 | grep -F "designated =>" || true
echo "$APP_DIR"
