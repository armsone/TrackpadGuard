#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"
DIST_DIR="$PROJECT_DIR/dist"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
APP_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
TAG="v$APP_VERSION"
DMG_PATH="$DIST_DIR/TrackpadGuard.dmg"
VERSIONED_DMG_PATH="$DIST_DIR/TrackpadGuard-$APP_VERSION.dmg"
SPARKLE_ROOT="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle"
GENERATE_APPCAST="$SPARKLE_ROOT/bin/generate_appcast"
SPARKLE_KEY_ACCOUNT=${SPARKLE_KEY_ACCOUNT:-TrackpadGuard}
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:-"Developer ID Application: BYOUNG KI HAN (T7B4EPLHPK)"}
NOTARY_PROFILE=${NOTARY_PROFILE:-ccmb-notary}
RELEASE_NOTES_PATH=${1:-}

if [[ $(git -C "$PROJECT_DIR" branch --show-current) != "main" ]]; then
  echo "릴리스는 main 브랜치에서만 게시할 수 있습니다." >&2
  exit 65
fi
if ! git -C "$PROJECT_DIR" diff --quiet || ! git -C "$PROJECT_DIR" diff --cached --quiet; then
  echo "릴리스 전에 추적 중인 변경을 커밋해야 합니다." >&2
  exit 65
fi
if [[ ! -f "$PROJECT_DIR/Configuration/SparklePublicKey.txt" ]]; then
  echo "TrackpadGuard 전용 Sparkle 공개 키가 필요합니다." >&2
  exit 66
fi
gh auth status >/dev/null
if gh release view "$TAG" --repo armsone/TrackpadGuard >/dev/null 2>&1; then
  echo "이미 존재하는 GitHub Release입니다: $TAG" >&2
  exit 65
fi

CODESIGN_IDENTITY="$CODESIGN_IDENTITY" NOTARY_PROFILE="$NOTARY_PROFILE" \
  "$SCRIPT_DIR/package-macos.sh" --notarize

WORK_DIR=$(mktemp -d "$DIST_DIR/.release.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT
ditto "$DMG_PATH" "$WORK_DIR/TrackpadGuard-$APP_VERSION.dmg"
if [[ -f "$APPCAST_PATH" ]]; then
  ditto "$APPCAST_PATH" "$WORK_DIR/appcast.xml"
fi
if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  ditto "$RELEASE_NOTES_PATH" "$WORK_DIR/TrackpadGuard-$APP_VERSION.md"
else
  printf '# TrackpadGuard %s\n\n키 입력 중 트랙패드 오작동 방지와 사용자 지정 해제 영역을 제공하는 첫 공개 버전입니다.\n' "$APP_VERSION" > "$WORK_DIR/TrackpadGuard-$APP_VERSION.md"
fi

"$GENERATE_APPCAST" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/armsone/TrackpadGuard/releases/download/$TAG/" \
  --link "https://github.com/armsone/TrackpadGuard/releases/tag/$TAG" \
  --maximum-deltas 0 \
  --maximum-versions 3 \
  --embed-release-notes \
  -o "$WORK_DIR/appcast.xml" \
  "$WORK_DIR"

ditto "$WORK_DIR/TrackpadGuard-$APP_VERSION.dmg" "$VERSIONED_DMG_PATH"
ditto "$WORK_DIR/appcast.xml" "$APPCAST_PATH"
gh release create "$TAG" "$VERSIONED_DMG_PATH" \
  --repo armsone/TrackpadGuard \
  --title "TrackpadGuard $APP_VERSION" \
  --notes-file "$WORK_DIR/TrackpadGuard-$APP_VERSION.md"

git -C "$PROJECT_DIR" add appcast.xml
git -C "$PROJECT_DIR" commit -m "Publish TrackpadGuard $APP_VERSION appcast"
git -C "$PROJECT_DIR" push origin main

echo "TrackpadGuard $APP_VERSION ($APP_BUILD) 게시 완료: https://github.com/armsone/TrackpadGuard/releases/tag/$TAG"
