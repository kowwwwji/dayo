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
