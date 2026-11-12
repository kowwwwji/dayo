# Dayo

予定（Google カレンダー）と Todo（iCloud リマインダー）を 1 本の時間軸で確認・入力する Mac アプリ。
データは Mac に登録したアカウントのものを読み書きするだけで、独自のサーバーや保存先は持たない。

- 設計と画面・キー操作の仕様: [docs/DESIGN.md](docs/DESIGN.md)
- Mac App Store への提出: [docs/app-store/README.md](docs/app-store/README.md)

## Mac に入れる

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

## Mac ごとに用意するもの

- **アカウント**: 「システム設定 → インターネットアカウント」に Google と iCloud を追加する。Dayo はそこに同期された予定とリマインダーを表示する。
- **設定**: 表示の切替や一日の開始・終了時刻などは Mac ごとに保存され、同期されない。
