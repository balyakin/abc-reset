#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$project_dir"

app_dir="$project_dir/dist/ABC Reset.app"
deployment_target="12.0"
architecture="$(uname -m)"

mkdir -p "$app_dir/Contents/MacOS"
xcrun swiftc -O -parse-as-library \
    -target "$architecture-apple-macosx$deployment_target" \
    "$project_dir"/Sources/ABCReset/*.swift \
    -o "$app_dir/Contents/MacOS/ABCReset"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --strict "$app_dir"

printf '\nГотово: %s\nЗапуск: open "%s"\n' "$app_dir" "$app_dir"
