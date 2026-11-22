#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'macOSで実行してください。' >&2
    exit 1
fi
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$repo_dir/.build/install"
destination="${1:-$HOME/Applications}"
app="$destination/NanoDesk.app"
if pgrep -x NanoDesk >/dev/null; then
    echo 'NanoDeskをメニューから終了して再実行してください。' >&2
    exit 1
fi
if [[ -e "$app" ]]; then
    echo "$app は既に存在します。別の場所へ移動してから再実行してください。" >&2
    exit 1
fi
xcodebuild -project "$repo_dir/NanoDesk.xcodeproj" -scheme NanoDesk \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$build_dir" build
built_app="$build_dir/Build/Products/Release/NanoDesk.app"
codesign --verify --deep --strict "$built_app"
mkdir -p "$destination"
staging="$(mktemp -d "$destination/.nanodesk-install.XXXXXXXX")"
trap 'rmdir "$staging" 2>/dev/null || true' EXIT
ditto "$built_app" "$staging/NanoDesk.app"
codesign --verify --deep --strict "$staging/NanoDesk.app"
mv -n "$staging/NanoDesk.app" "$app"
echo "インストールしました: $app"
open "$app"
