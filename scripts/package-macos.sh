#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$DIST_DIR/TrackpadGuard.app"
LOCAL_DMG_PATH="$DIST_DIR/TrackpadGuard-local.dmg"
RELEASE_DMG_PATH="$DIST_DIR/TrackpadGuard.dmg"
INSTALL_GUIDE="$PROJECT_DIR/INSTALL.md"
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
NOTARY_PROFILE=${NOTARY_PROFILE:-}
NOTARIZE=false

if [[ "${1:-}" == "--notarize" ]]; then
  NOTARIZE=true
elif [[ $# -gt 0 ]]; then
  echo "사용법: $0 [--notarize]" >&2
  exit 64
fi

if [[ "$NOTARIZE" == true ]]; then
  if [[ "$CODESIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "공증 배포에는 Developer ID Application 인증서가 필요합니다." >&2
    exit 64
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "공증 배포에는 NOTARY_PROFILE이 필요합니다." >&2
    exit 64
  fi
  if [[ ! -f "$PROJECT_DIR/Configuration/SparklePublicKey.txt" ]]; then
    echo "공증 배포에는 TrackpadGuard 전용 Sparkle 공개 키가 필요합니다." >&2
    exit 66
  fi
fi

CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$SCRIPT_DIR/build-app.sh"

if [[ "$NOTARIZE" == true ]]; then
  NOTARY_ZIP="$DIST_DIR/TrackpadGuard-notary.zip"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

PACKAGE_DIR=$(mktemp -d "$DIST_DIR/.package.XXXXXX")
trap 'rm -rf "$PACKAGE_DIR"' EXIT
ditto "$APP_PATH" "$PACKAGE_DIR/TrackpadGuard.app"
ditto "$INSTALL_GUIDE" "$PACKAGE_DIR/설치 및 사용 안내.md"
ln -s /Applications "$PACKAGE_DIR/Applications"

DMG_PATH="$LOCAL_DMG_PATH"
if [[ "$NOTARIZE" == true ]]; then
  DMG_PATH="$RELEASE_DMG_PATH"
fi
hdiutil create -volname TrackpadGuard -srcfolder "$PACKAGE_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

if [[ "$NOTARIZE" == true ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --strict --verbose=4 "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

echo "$DMG_PATH"
