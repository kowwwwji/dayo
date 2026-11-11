#!/bin/bash
# scripts/make-icon.swift の図柄から App/Assets.xcassets/AppIcon.appiconset の画像を作り直す。
set -euo pipefail

cd "$(dirname "$0")/.."

SET="App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$SET"

swift scripts/make-icon.swift "$SET/mac-1024.png"
swift scripts/make-icon.swift "$SET/ios-1024.png" --full-bleed

for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$SET/mac-1024.png" --out "$SET/mac-$size.png" > /dev/null
done

# Mac の Dock で今日の日付を載せる台紙（App/DockIcon.swift）
BASE="App/Assets.xcassets/DockIconBase.imageset"
mkdir -p "$BASE"
swift scripts/make-icon.swift "$BASE/dock-base.png" --blank
sips -z 512 512 "$BASE/dock-base.png" > /dev/null
