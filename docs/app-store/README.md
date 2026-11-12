# Mac App Store への提出

Mac 版を、個人の開発者登録で、無料・日本だけに出す。貼る内容は [listing.md](listing.md)、
サポートとプライバシーポリシーのページは [site/](site/)（ソースを見せないため、このリポジトリとは別の公開用リポジトリで GitHub Pages に出す）。

## 最初の 1 回

1. **開発者登録**: developer.apple.com の Apple Developer Program に個人で登録する（Apple ID の 2 ファクタ認証と年会費の支払いが要る）。承認まで数時間〜2 日。
2. **Xcode にサインイン**: Xcode → 設定 → アカウントで、登録した Apple ID を追加する。表示されるチーム ID（10 桁の英数字）を
   `project.yml` の Release の `DEVELOPMENT_TEAM` に入れる。
3. **Bundle ID を登録**: developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → ＋ → App IDs → App。
   Description は `Dayo`、Bundle ID は Explicit で `com.kowwwwji.Dayo`、Capabilities は何も付けない。
4. **App を作る**: App Store Connect → アプリ → ＋ → 新規 App。プラットフォームは macOS、名前は [listing.md](listing.md)、
   主言語は日本語、Bundle ID は 3. のもの、SKU は `dayo-mac`（自分で区別できれば何でもよい）、ユーザアクセスは制限なし。
5. **サポートのページを出す**: [site/](site/) の 3 ファイルを公開用リポジトリに置き、GitHub Pages で公開する。
   URL が [listing.md](listing.md) のものと変わったら、そちらも直す。
6. **価格と配信**: 「価格および配信状況」で無料、配信する国は日本だけ。

## ビルドを送る（バージョンごと）

1. `project.yml` の `MARKETING_VERSION`（表示するバージョン）を必要なら上げ、`CURRENT_PROJECT_VERSION`（ビルド番号）は送るたびに上げる（同じ番号は送れない）。
2. `scripts/archive.sh` を実行する。初回は証明書を作るため、キーチェーンのパスワードを聞かれることがある。
3. 送り方はどちらか:
   - `build/AppStore/` の `.pkg` を Transporter（Mac App Store から入れる）にドラッグして「配信」
   - `open build/Dayo.xcarchive` で Xcode の Organizer を開き、Distribute App → App Store Connect → Upload
4. 数分〜数十分で App Store Connect の「ビルド」に出る。

## 審査に出す

1. App Store Connect のバージョンのページで、[listing.md](listing.md) の内容を貼り、[screenshots/](screenshots/) の 5 枚を入れる。
2. 「ビルド」で送ったビルドを選ぶ。
3. 「App のプライバシー」と「年齢制限」を [listing.md](listing.md) のとおりに答える。
4. 「審査用に追加」→「審査へ提出」。

## スクリーンショットを撮り直す

デモ表示（Debug ビルドだけの起動引数 `-demo YES`）は架空の予定とリマインダーを出し、カレンダーとリマインダーには触れない。
中身は曜日ごとに決まっていて、今日より前のリマインダーは完了済みになる。

```sh
xcodegen generate
xcodebuild -project Dayo.xcodeproj -scheme Dayo -destination 'platform=macOS' -derivedDataPath DerivedData build
open -n DerivedData/Build/Products/Debug/Dayo.app --args -demo YES -timelineMode week -ApplePersistenceIgnoreState YES
```

ウインドウを 1440×900pt にして、Retina の画面で撮ると 2880×1800px になる（`screencapture -o -l <ウインドウ ID>`）。
App Store Connect は透過のある画像を受け付けないので、角の透過を埋めてから使う:

```sh
magick shot.png -background '#1e1e1e' -alpha remove -alpha off shot.png
```
