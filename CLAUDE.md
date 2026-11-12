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
- 普段使いのアプリを入れる・更新するのは `scripts/install.sh`（手順と署名の理由は `README.md`）
- Debug ビルドの Bundle ID は `com.kowwwwji.Dayo.dev`。入れたアプリ（`com.kowwwwji.Dayo`）とは設定も許可も別なので、確認用の起動で普段使いの設定は変わらない
- アイコンの図柄は `scripts/make-icon.swift`。変えたら `scripts/make-appiconset.sh` でアセットを作り直す
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
- 確認用インスタンスに `⌘1`〜`⌘3` や `⌘s` を送ると、Debug ビルドの保存済みの設定が書き換わる（起動引数が上書きするのは読み出しだけ）。確認後に元の値へ戻すか、変えたことを報告する
- 撮った画像の一部を切り出すのは `magick in.png -crop 幅x高さ+0+0 +repage out.png`。`sips -c` は中央から切るので上端を取れない
- `open -n -g` で起動してもウインドウが出ないときは、起動引数に `-ApplePersistenceIgnoreState YES` を足す（ウインドウを閉じた状態が保存されていると、その状態が復元される）
- `swift test` は `timeout 300 swift test` で走らせる。モデルの処理を待つテストは、実装前だと待ち続けて終わらないことがある
- `WindowGroup` は、保存するウインドウの位置と大きさの名前を中身のビューの型から作る。`RootView` に外から修飾子を付けると名前が変わり、位置を忘れる。修飾子は `RootView` の中に付ける
- 「入れ直しても許可が引き継がれる」の確認は、中身の違うビルドで行う（`CURRENT_PROJECT_VERSION` を一時的に変えて `scripts/install.sh`、`codesign -dv --verbose=4` で CDHash が変わったことを見る）。同じビルドの入れ直しは CDHash が同じで確認にならない
- 自己署名の証明書は `security find-identity -p codesigning` に `CSSMERR_TP_NOT_TRUSTED` と出るが、`codesign` はそのまま使える（`-v` を付けると一覧に出ない）
- シェルスクリプトで変数の直後に日本語を続けるときは `${VAR}` と書く（`"$VAR」"` は変数名の一部として読まれ、unbound variable になる）
- 自分が起動していない Dayo のプロセス（別の worktree のビルドなど）は終了できない。ユーザーに終了を頼む
- 確認用インスタンスへ変更するキー（`d`、`x`、`⇧j`、`⌥j`）を送る前に、ウインドウを撮って表示中の日と選択の枠を確かめる。移動・選択・変更を 1 回のコマンドにまとめない（起動直後やポップオーバーを開いた直後のキーは届かないことがある）
- 変更を伴う確認は、遠い先の空いた日に自分で作った項目で行う（`⌘g` → 「2027/1/31」で移動 → クイック入力で「1/31 10時-11時 名前 @予定」）。終わったら `d` で消し、10 秒待って消えたことを見る
- 背面のインスタンスへ文字を打つときは、`CGEvent.keyboardSetUnicodeString` で 1 文字ずつ送る（日本語も入る）。`⌘a` などメニューのショートカットは背面では効かない
- 確認用インスタンスへキーを送るスクリプトは `swift key.swift <pid> ...` のようにインタプリタで動かす。`swiftc` でビルドしたバイナリからの `CGEvent.postToPid` は、エラーにならないまま届かない
- 確認用インスタンスのログは `FileHandle.standardError` へ書き、`open --stderr <ファイル>` で受ける（`print` は溜め込まれて出てこない）。受けているファイルへ自分で追記しない
- `screencapture -l` に渡すウインドウは、ポップオーバーの開閉直後だと別のもの（真っ白な 500×500）を拾うことがある。少し待って撮り直す
- 予定の `TimelineItem.id` は開始時刻を含む。日時を変えると読み直しで別の id になるので、選択や取り消しの対象は `calendarItemIdentifier` と開始日時で引き直す
- 保存の直後に変更通知の読み込みが走り、保存後の読み直しを追い越す。モデルのテストは `FakeSource.gate` で 2 つの読み込みの順を入れ替えて書く
- DayoCore では `/.../` の正規表現リテラルがコンパイルエラーになる。`#/.../#` と書く
- テスト用の取得元は保存しても `snapshots` を書き換えない。保存後の内容を見たいテストは、操作の前に `snapshots` を変更後の内容へ差し替える
- 背面の確認用インスタンスでも `⌘n`（キーコード 45 + command）は `CGEvent.postToPid` で届き、クイック入力へフォーカスが入る。続けて文字を送り、return の前にウインドウを撮って入力欄の中身を確かめる
- サイドバーの「期日なし」の確認用の項目は、クイック入力に日付なしでタイトルだけ打って作る。サイドバーの行はキーで選べないので、自分では消せない（ユーザーに消してもらうか、確認に使ってもらう）
- 値を取らない起動引数（`-flag` だけ）を `-ApplePersistenceIgnoreState YES` の前に置くと、次の引数を値として食ってウインドウが出なくなる。確認用の引数は必ず `-名前 値` の形にする
- OS のドラッグ＆ドロップ（`onDrag`）の出どころを `List` の行にしない。落とした先から戻ってきた行が、次のクリックまで描かれない
- ポップオーバー（情報カード、詳細編集）は別のウインドウ。出ているかは、その PID のレイヤー 0 のウインドウの数で分かる。撮るときはポップオーバーのウインドウ ID を `screencapture -l` に渡すと、親ウインドウごと写る
- 背面のインスタンスでは、詳細編集のポップオーバーを開いた直後の esc が届かないことがある。ウインドウの数で閉じたかを確かめ、残っていればもう一度送る
- 先の日で完了にしたリマインダーは画面から消える（選択も外れる）。確認用のリマインダーを `x` で完了したら、`u` で戻してから `d` で消す
- 情報カードが出ている間のキーは、カードのウインドウ宛てに届く。タイムラインのキーを足すときは、カードを出したままでも効くかを確かめる
- `RecurrenceSpec` には曜日・日を補う関数が 2 つある（将来回の展開用の `filled`、比較と説明用の `normalized`）。補い方が違うので、まとめない
- この Mac は「キーボードナビゲーション」が有効（`AppleKeyboardUIMode = 2`）。ポップオーバーを開くと最初のボタンやリンクに枠が付くので、自前でフォーカスを扱う所は `.focusable(false)` にする
