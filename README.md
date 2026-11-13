# Dayo

予定（Google カレンダー）と Todo（iCloud リマインダー）を 1 本の時間軸で確認・入力する Mac アプリ。
データは Mac に登録したアカウントのものを読み書きするだけで、独自のサーバーや保存先は持たない。

- 設計と画面・キー操作の仕様: [docs/DESIGN.md](docs/DESIGN.md)
- Mac App Store への提出: [docs/app-store/README.md](docs/app-store/README.md)

## 使う

macOS 14 以降（Apple シリコン / Intel）。

1. [Releases](https://github.com/kowwwwji/dayo/releases/latest) から `Dayo-<版>.dmg` をダウンロードして開く
2. `Dayo` を `Applications` へドラッグする
3. 「アプリケーション」の Dayo を開く。初回は「開発元を確認できない」という旨の警告が出て開けないので、
   「システム設定 → プライバシーとセキュリティ」の下のほうにある「このまま開く」を押して、もう一度開く
   （Apple の有料の開発者登録をしておらず、Apple の確認（公証）を受けていないため。許可は最初の 1 回だけ）
4. カレンダーとリマインダーへのアクセスを許可する

予定やリマインダーは「システム設定 → インターネットアカウント」に追加したアカウントのものが出る。
`?` キーでキー操作の一覧が出る。

更新は、新しい dmg で同じように `Applications` へドラッグして置き換える（動いている Dayo は先に終了する）。アクセスの許可は引き継がれる。
不具合・要望は [Issues](https://github.com/kowwwwji/dayo/issues) へ。

## ソースからビルドして入れる

Mac ごとにその場でビルドして入れる。必要なのは Xcode と `xcodegen`（`brew install xcodegen`）。

```sh
ghq get kowwwwji/dayo && cd "$(ghq root)/github.com/kowwwwji/dayo"
scripts/create-signing-cert.sh   # 最初の 1 回だけ。キーチェーンのパスワードを聞かれることがある
scripts/install.sh               # /Applications/Dayo.app へ入れて起動する
```

初回の起動で、カレンダーとリマインダーへのアクセスを許可する。

更新するときは `git pull` して `scripts/install.sh` をもう一度実行する（動いている Dayo は一度終了する）。

### 署名用の証明書を作る理由

Apple の開発者登録をしていないので、その Mac だけで通用する自己署名の証明書で署名する。
毎回同じ証明書で署名しておくと、更新しても macOS が同じアプリと見なし、カレンダーとリマインダーの許可を聞き直されない。

ビルド済みの `Dayo.app` を別の Mac へコピーして使うこともできるが、公証を受けていないので macOS が起動を止める
（「システム設定 → プライバシーとセキュリティ」で手で許可する）。その Mac でビルドするほうが手間が少ない。

## 新しい版を出す

dmg をこのリポジトリの Releases に置く。

```sh
scripts/make-dmg.sh   # build/Dayo-<版>.dmg を作る
gh release create v<版> build/Dayo-<版>.dmg --title "Dayo <版>" --notes "<変更点>"
```

版を上げるときは `project.yml` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を上げてから作る。
公証を受けていないので、使う人は初回の起動を「システム設定 → プライバシーとセキュリティ」で許可する。

## iPhone に入れる

無料の Apple ID（Personal Team）で署名して、つないだ iPhone へ入れる。最初に Xcode でその Apple ID にサインインし、
iPhone の「設定 → プライバシーとセキュリティ → デベロッパモード」をオンにしておく。

```sh
scripts/install-iphone.sh   # iPhone をつないでロックを解除してから
```

初回は iPhone の「設定 → 一般 → VPN とデバイス管理」で開発元を信頼する。無料の署名は 7 日で切れるので、
切れたら同じコマンドで入れ直す。チーム ID は `project.yml` の `DEVELOPMENT_TEAM[sdk=iphoneos*]`（別の Apple ID で入れるなら書き換える）。

## Mac ごとに用意するもの

- **アカウント**: 「システム設定 → インターネットアカウント」に Google と iCloud を追加する。Dayo はそこに同期された予定とリマインダーを表示する。
- **設定**: 表示の切替や一日の開始・終了時刻などは Mac ごとに保存され、同期されない。
