#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_RUNTIME="$ROOT_DIR/Sources/FocusCore/Resources/focus-runtime.js"
KOTLIN_RUNTIME="$ROOT_DIR/focus-core/src/commonMain/resources/focus-runtime.js"
MODE="${1:---check}"

usage() {
  printf 'Usage: %s [--check|--sync]\n' "$0"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

case "$MODE" in
  --sync)
    cp "$CANONICAL_RUNTIME" "$KOTLIN_RUNTIME"
    printf 'Synchronized focus-runtime.js (%s)\n' "$(sha256 "$CANONICAL_RUNTIME")"
    ;;
  --check)
    if ! cmp -s "$CANONICAL_RUNTIME" "$KOTLIN_RUNTIME"; then
      printf 'focus-runtime.js copies differ.\n' >&2
      printf 'canonical: %s  %s\n' "$(sha256 "$CANONICAL_RUNTIME")" "$CANONICAL_RUNTIME" >&2
      printf 'mirror:    %s  %s\n' "$(sha256 "$KOTLIN_RUNTIME")" "$KOTLIN_RUNTIME" >&2
      printf 'Run ./Scripts/sync_focus_runtime.sh --sync and commit both files.\n' >&2
      exit 1
    fi
    printf 'focus-runtime.js is synchronized (%s)\n' "$(sha256 "$CANONICAL_RUNTIME")"
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
