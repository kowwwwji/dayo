#!/bin/bash
# つないでいる iPhone へ Release ビルドを入れて起動する。更新も同じコマンド。
# 無料の Apple ID（Personal Team）の署名は 7 日で切れるので、切れたらこれで入れ直す。
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.kowwwwji.Dayo"
APP="DerivedData/Build/Products/Release-iphoneos/Dayo.app"

# つながっている iPhone を 1 台選ぶ（USB か、同じネットワークでペアリング済みのもの）
device="$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')"
if [ -z "$device" ]; then
    echo "iPhone が見つかりません。Mac につないで、ロックを解除してから実行してください。" >&2
    exit 1
fi

xcodegen generate
xcodebuild -project Dayo.xcodeproj -scheme Dayo -configuration Release \
    -destination "id=$device" -derivedDataPath DerivedData -allowProvisioningUpdates -quiet build

xcrun devicectl device install app --device "$device" "$APP"
# 初回は iPhone の「設定 → 一般 → VPN とデバイス管理」で開発元を信頼するまで起動できない
if ! xcrun devicectl device process launch --device "$device" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "入れました。起動できなかったので、iPhone の「設定 → 一般 → VPN とデバイス管理」で開発元を信頼してから、ホーム画面の Dayo を開いてください。"
    exit 0
fi
echo "iPhone に Dayo を入れて起動しました。"
