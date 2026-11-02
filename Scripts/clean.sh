#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-}"

usage() {
  printf 'Usage: %s [--gradle]\n' "$0"
}

case "$MODE" in
  "") ;;
  --gradle) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"
rm -rf build .build .kotlin focus-core/build focus-android/build
find . -maxdepth 1 -type d -name '.tmp-*' -exec rm -rf {} +

if [[ "$MODE" == "--gradle" ]]; then
  rm -rf .gradle .gradle-home
fi

printf 'Cleaned build outputs%s\n' "$([[ "$MODE" == "--gradle" ]] && printf ' and Gradle caches')"
