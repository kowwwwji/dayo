#!/bin/bash
# Mac App Store に出す Release のアーカイブを作り、App Store Connect 向けに書き出す。
# アップロードは書き出した .pkg を Transporter で送るか、Xcode の Organizer でアーカイブから行う（手順は docs/app-store/README.md）。
#
# チーム ID は project.yml の Release の DEVELOPMENT_TEAM から読む。空なら署名せずにアーカイブだけ作る
# （Apple Developer Program の承認前に、アーカイブが作れることを確かめるため）。
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="build/Dayo.xcarchive"
EXPORT_DIR="build/AppStore"

xcodegen generate

# 一覧を受けてから探す（パイプのまま読むと、pipefail の下で失敗が見えなくなる）
settings="$(xcodebuild -project Dayo.xcodeproj -target Dayo -configuration Release -showBuildSettings)"
team="$(awk '$1 == "DEVELOPMENT_TEAM" && $3 != "" { print $3 }' <<< "$settings" | head -n 1)"
if [ -n "$team" ] && ! [[ "$team" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "project.yml の DEVELOPMENT_TEAM「${team}」はチーム ID（英大文字と数字 10 桁）の形ではありません。" >&2
    exit 1
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"

if [ -z "$team" ]; then
    xcodebuild -project Dayo.xcodeproj -scheme Dayo -configuration Release \
        -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -quiet \
        archive CODE_SIGNING_ALLOWED=NO
    echo "project.yml の Release に DEVELOPMENT_TEAM が無いので、署名せずに ${ARCHIVE} を作りました（提出には使えません）。"
    exit 0
fi

# project.yml のアドホック署名（install.sh 用）を、Apple の証明書での自動署名に替える。
# 証明書とプロファイルは Xcode にサインインしたアカウントから作られる（-allowProvisioningUpdates）。
xcodebuild -project Dayo.xcodeproj -scheme Dayo -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -quiet -allowProvisioningUpdates \
    archive CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$team"

options="$(mktemp -t dayo-export.XXXXXX)"
trap 'rm -f "$options"' EXIT
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>teamID</key>
	<string>${team}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$options" -allowProvisioningUpdates -quiet

echo "${EXPORT_DIR} に書き出しました。中の .pkg を Transporter で App Store Connect へ送ってください。"
