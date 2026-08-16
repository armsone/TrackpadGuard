#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/TrackpadGuard.app"
CONTENTS_DIR="$APP_DIR/Contents"
CONFIGURATION=${CONFIGURATION:-release}
ARCHS=${ARCHS:-"arm64 x86_64"}
BUILD_ROOT="$PROJECT_DIR/.build/distribution"

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

SIGNING_IDENTITY=${CODESIGN_IDENTITY:-${SIGNING_IDENTITY:--}}
SIGN_OPTIONS=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGN_OPTIONS+=(--timestamp)
fi
codesign $SIGN_OPTIONS "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign $SIGN_OPTIONS "$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign $SIGN_OPTIONS "$CONTENTS_DIR/Frameworks/Sparkle.framework"
codesign $SIGN_OPTIONS \
  --entitlements "$PROJECT_DIR/Resources/TrackpadGuard.entitlements" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
