#!/bin/bash
# 他の人に配る dmg を作る（build/Dayo-<版>.dmg）。Intel と Apple シリコンの両方で動くビルドにする。
# 署名は install.sh と同じ自己署名の証明書で行う。毎回同じ証明書で署名すると、相手の Mac でも
# 更新のたびにカレンダーとリマインダーの許可を聞き直されない。公証は受けていないので、相手は初回の起動を手で許可する。
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="Dayo Local Signing"
DERIVED="DerivedData/Distribution"
BUILT="$DERIVED/Build/Products/Release/Dayo.app"
STAGE="build/dmg"

identities="$(security find-identity -p codesigning)"
if ! grep -q "\"$IDENTITY\"" <<< "$identities"; then
    echo "署名用の証明書「${IDENTITY}」がありません。先に scripts/create-signing-cert.sh を実行してください。" >&2
    exit 1
fi

xcodegen generate
# 特定の Mac を指さないと、両方の CPU 向けにビルドされる
xcodebuild -project Dayo.xcodeproj -scheme Dayo -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -quiet clean build

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$BUILT/Contents/Info.plist")"
dmg="build/Dayo-${version}.dmg"

# dmg の中身: アプリと「アプリケーション」への別名（ドラッグで入れられるように）
rm -rf "$STAGE" "$dmg"
mkdir -p "$STAGE"
ditto "$BUILT" "$STAGE/Dayo.app"
codesign --force --sign "$IDENTITY" --options runtime --entitlements App/Dayo.entitlements "$STAGE/Dayo.app"
codesign --verify --strict "$STAGE/Dayo.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Dayo" -srcfolder "$STAGE" -format UDZO -ov "$dmg" > /dev/null
rm -rf "$STAGE"

echo "$dmg を作りました（$(lipo -archs "$BUILT/Contents/MacOS/Dayo")）。"
