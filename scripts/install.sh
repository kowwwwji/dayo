#!/bin/bash
# Release ビルドを /Applications/Dayo.app として入れて起動する。更新も同じコマンド。
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="Dayo Local Signing"
DEST="/Applications/Dayo.app"
BUILT="DerivedData/Build/Products/Release/Dayo.app"
STAGED="DerivedData/Install/Dayo.app"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "署名用の証明書「${IDENTITY}」がありません。先に scripts/create-signing-cert.sh を実行してください。" >&2
    exit 1
fi

xcodegen generate
xcodebuild -project Dayo.xcodeproj -scheme Dayo -configuration Release \
    -destination 'platform=macOS' -derivedDataPath DerivedData -quiet build

# 署名は入れる前の写しで済ませる。失敗したときに、入っているアプリを壊さないため。
rm -rf "$STAGED"
mkdir -p "$(dirname "$STAGED")"
ditto "$BUILT" "$STAGED"
codesign --force --sign "$IDENTITY" --entitlements App/Dayo.entitlements "$STAGED"
codesign --verify --strict "$STAGED"

# 入っている Dayo だけを終了する（開発用のビルドは別の場所から動いているので触らない）
running() { pgrep -f "^$DEST/Contents/MacOS/Dayo" || true; }
pids="$(running)"
if [ -n "$pids" ]; then
    kill $pids
    for _ in $(seq 50); do
        [ -z "$(running)" ] && break
        sleep 0.1
    done
    if [ -n "$(running)" ]; then
        echo "動いている Dayo を終了できませんでした。終了してからやり直してください。" >&2
        exit 1
    fi
fi

rm -rf "$DEST"
ditto "$STAGED" "$DEST"
rm -rf "$STAGED"

open "$DEST"
echo "$DEST を入れて起動しました。"
