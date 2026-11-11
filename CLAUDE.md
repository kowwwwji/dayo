# Dayo

予定（Googleカレンダー）とTodo（iCloudリマインダー）を1本の時間軸で確認・入力できる、Mac + iPhone向けSwiftUIアプリ。

- 設計書: `docs/DESIGN.md`（判断に迷ったらまずここを読む）
- データは EventKit 経由で読み書きするだけ。独自サーバー・独自の永続化・通知処理は作らない
- EventKit への依存は `EventKitRepository`（`CalendarSource` protocol）に閉じ込め、画面は `TimelineItem` だけを扱う
- クイック入力は `protocol InputParser`。日本語パーサーは入力→期待結果のテーブルテストで育てる
- 最低対象OS: macOS 14 / iOS 17（`requestFullAccessToReminders` / `requestFullAccessToEvents` を使うため）
- MVPの範囲は設計書「スコープとMVP」に従う。範囲外の機能は提案に留め、勝手に実装しない

## ビルド・テスト

- `xcodegen generate` で `Dayo.xcodeproj` を生成する（`project.yml` が正。`.xcodeproj` と `App/Info.plist` は生成物で git 管理外）
- ドメイン層は `Packages/DayoCore`。テストは `cd Packages/DayoCore && swift test`（Swift Testing）
- アプリは `xcodebuild -project Dayo.xcodeproj -scheme Dayo -destination 'platform=macOS' -derivedDataPath DerivedData build`。起動は `open DerivedData/Build/Products/Debug/Dayo.app`。Mac はアドホック署名、iOS は `DEVELOPMENT_TEAM` 未設定のためシミュレータのみ
- iOS のビルド確認は `xcodebuild -project Dayo.xcodeproj -scheme Dayo -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build`
- 画面確認は `open -n -g DerivedData/Build/Products/Debug/Dayo.app --args -timelineMode week`（`-キー 値` はその起動だけ `@AppStorage` を上書きし、保存済みの設定は変えない）。撮るのは `screencapture -l <ウィンドウID>` で Dayo のウィンドウだけ。全画面は作業中の別アプリが写る
- Swift Testing の `#expect` に `allSatisfy { ... }` など rethrows のクロージャを直接書くとコンパイルエラーになる。`map(\.x) == [...]` の形で比べる
- SwiftUI の `.offset` で置いたビューは `ScrollViewReader.scrollTo` の行き先にならない（配置上の位置が変わらないため）。行き先には `alignmentGuide` で位置を持たせた目印を置く
- `DateInterval.contains` は終端を含む。「翌日 0:00 は含めない」判定は `start <= x && x < end` で書く
- キー操作の確認は、`open -n -g` で背面起動したインスタンスへ `CGEvent.postToPid` でキーを送る（前面に出さずに届く）。Dayo はレイヤー 0 のウインドウを 2 つ持つので、`screencapture -l` には面積が最大のものを渡す
- 確認用インスタンスには `-keyCheck 1` のような固有の起動引数を付け、終了は `pgrep -f` でその引数を持つ PID だけにする
- Mac のウインドウは first responder が空だと最初の入力欄へフォーカスを入れる（起動直後と、ポップオーバーを閉じた直後）。入力欄以外でキーを受けたいなら、first responder を持つビューを置く
- `#if os(macOS)` の 1 ブロックに、シーンの修飾子（`.commands`）と別のシーン（`Settings`）を混ぜるとコンパイルエラーになる。ブロックを分ける
- 新しい worktree で初めて起動したビルドは、カレンダー / リマインダーの許可ダイアログが出る（アドホック署名で別のアプリ扱い）。許可されるまで画面は読み込み中のまま。ダイアログはユーザーに押してもらう
- 確認用インスタンスに `⌘1`〜`⌘3` や `⌃⌘s` を送ると、保存済みの設定が書き換わる（起動引数が上書きするのは読み出しだけ）。確認後に元の値へ戻すか、変えたことを報告する
- 撮った画像の一部を切り出すのは `magick in.png -crop 幅x高さ+0+0 +repage out.png`。`sips -c` は中央から切るので上端を取れない
- `open -n -g` で起動してもウインドウが出ないときは、起動引数に `-ApplePersistenceIgnoreState YES` を足す（ウインドウを閉じた状態が保存されていると、その状態が復元される）
- `swift test` は `timeout 300 swift test` で走らせる。モデルの処理を待つテストは、実装前だと待ち続けて終わらないことがある
