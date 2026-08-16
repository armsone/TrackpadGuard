#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
COMMAND=${1:-build}
if (( $# > 0 )); then
  shift
fi

mkdir -p \
  "$PROJECT_DIR/.build/cache" \
  "$PROJECT_DIR/.build/config" \
  "$PROJECT_DIR/.build/security" \
  "$PROJECT_DIR/.build/module-cache"

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/module-cache"

exec swift "$COMMAND" \
  --cache-path "$PROJECT_DIR/.build/cache" \
  --config-path "$PROJECT_DIR/.build/config" \
  --security-path "$PROJECT_DIR/.build/security" \
  --disable-sandbox \
  "$@"
