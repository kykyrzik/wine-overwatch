#!/bin/bash
# Makes macOS ask for microphone access on behalf of a Sikarugir wrapper.
# The wrapper only ever preflights the permission, so the system prompt never appears on its own.
# Usage: ./grant-mic.sh /path/to/Wrapper.app
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 /path/to/Wrapper.app" >&2; exit 2; }
APP="${1%/}"
[ -d "$APP/Contents/SharedSupport/wine" ] || { echo "error: $APP is not a Sikarugir wrapper" >&2; exit 1; }
if pgrep -f "$APP/Contents" >/dev/null 2>&1; then
    echo "error: quit the game, Battle.net and the wrapper first (a running wrapper ignores the file we hand it)" >&2
    exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d /tmp/ow-mic.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

command -v clang >/dev/null || { echo "error: clang not found; install the Xcode Command Line Tools (xcode-select --install)" >&2; exit 1; }
clang -arch arm64 -arch x86_64 -fobjc-arc -framework AVFoundation -framework Foundation \
    -o "$WORK/mic-request" "$HERE/mic-request.m"
codesign -f -s - "$WORK/mic-request" 2>/dev/null

# The helper must be started by the wrapper's own Wine, so that macOS attributes the request to the wrapper.
printf '@echo off\r\nstart /unix %s/mic-request %s/result.txt\r\n' "$WORK" "$WORK" > "$WORK/mic.bat"
open -a "$APP" "$WORK/mic.bat"

echo "If macOS asks for microphone access for this wrapper, click Allow."
for _ in $(seq 1 90); do
    if [ -s "$WORK/result.txt" ] && grep -q granted "$WORK/result.txt"; then break; fi
    sleep 2
done

if grep -q 'status_after=3' "$WORK/result.txt" 2>/dev/null; then
    echo "microphone access granted"
else
    echo "microphone access NOT granted:" >&2
    cat "$WORK/result.txt" >&2 2>/dev/null || echo "  the helper did not run (the wrapper may still have been running)" >&2
    exit 1
fi
