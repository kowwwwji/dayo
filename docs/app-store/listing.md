# App Store Connect に貼る内容

手順は [README.md](README.md)。文字数の上限は App Store Connect の欄の上限。

## App 情報

| 欄 | 内容 |
|---|---|
| 名前（30 字） | Dayo（埋まっていれば下の案から） |
| サブタイトル（30 字） | 予定と Todo を 1 本の時間軸で |
| 主言語 | 日本語 |
| カテゴリ | 仕事効率化（2 つ目は無し） |
| コンテンツ配信権 | 第三者のコンテンツを含まない |
| 年齢制限 | 質問にはすべて「なし / いいえ」（予定やリマインダーの中身はユーザー自身のもの。アプリ内ブラウザ・メッセージ・広告・購入は無い） |
| 著作権 | 2026 （登録した氏名） |
| 価格 | 無料 |
| 配信する国 | 日本だけ |

名前の案（「Dayo」が使えないとき）: `Dayo - 予定とTodoの時間軸` / `Dayo カレンダー` / `Dayo Timeline`

## このバージョンの情報

### プロモーションテキスト（170 字）

```
Google カレンダーの予定と iCloud リマインダーの Todo を、1 本の時間軸に並べて見られます。「明日 15時 歯医者」と打つだけで登録。キーボードだけで選んで、動かして、片付けられます。
```

### 説明（4,000 字）

```
Dayo は、予定と Todo を 1 本の時間軸で確認・入力する Mac のカレンダーアプリです。

Mac に追加した Google や iCloud のカレンダーと、リマインダーをそのまま使います。予定はカレンダーに、Todo はリマインダーに保存されるので、iPhone の純正アプリや家族との共有リストとも、いつもどおり同期されます。

■ 予定と Todo を同じ時間軸に
・日 / 3 日 / 週表示。予定とリマインダーを同じグリッドに並べます
・期日を過ぎた Todo は上にまとめて表示
・期日のない Todo はサイドバーに。時間軸へドラッグすると期日が付きます
・カレンダーやリストごとに表示を切り替え

■ 1 行で登録
「明日 15時 歯医者 #家族」「金曜 10時-11時 面談 @仕事」「毎週月曜 9時 ゴミ出し」のように打つと、日時・繰り返し・保存先を読み取って登録します。入力中は読み取った内容をその場で表示します。

■ キーボードだけで操作
・j / k で項目を選び、space で詳細のカードを表示
・shift + j / k で 15 分ずつ動かす、option + j / k で長さを変える
・x で Todo を完了、d で削除、u で取り消し
・o で選んだ項目の後ろに新しい予定を追加
・? でキー操作の一覧

■ マウスでも
ドラッグで移動、下端のドラッグで長さを変更、ダブルクリックで新規登録、右クリックで編集。

■ プライバシー
Dayo は独自のサーバーを持たず、予定や Todo を外部へ送りません。データの収集や広告もありません。

カレンダーとリマインダーへのフルアクセスの許可が必要です。
```

### キーワード（100 字。カンマ区切り、空白なし）

```
カレンダー,リマインダー,タスク,スケジュール,タイムライン,週表示,キーボード,手帳,やること,スケジュール帳,日程
```

アプリ名・サブタイトルに含まれる語や他社の商標（Google など）はキーワードに入れない（審査ガイドライン 2.3.7）。

### サポート URL / プライバシーポリシー URL

- サポート: `https://kowwwwji.github.io/dayo-support/`
- プライバシーポリシー: `https://kowwwwji.github.io/dayo-support/privacy.html`

公開用リポジトリの名前を変えたら、ここと [site/](site/) のリンクも合わせる。

### スクリーンショット（2880×1800）

[screenshots/](screenshots/) の 5 枚をこの順で。中身はデモ表示（架空の予定）。撮り直す手順は [README.md](README.md)。

## App のプライバシー

- 「データの収集」: **いいえ、このアプリからデータを収集しません**
  （予定とリマインダーは Mac の中で読み書きするだけで、開発者や第三者へ送らない）

## 審査へのメモ（App Review に関する情報）

サインインは不要（「サインインが必要です」のチェックは外す）。メモ欄:

```
Dayo shows the user's calendars and reminders (EventKit) on a single timeline and lets them add and edit items. It requires full access to Calendars and Reminders, which is requested on first launch; without it the app shows a message explaining how to grant access.

Dayo has no server and sends no data off the device. Everything is read from and written to the calendars and reminder lists already set up on the Mac (iCloud, Google, etc.).

To try it: type "明日 15時 テスト" (tomorrow 3 pm, "test") into the input field at the top and press Return to create an event. Select items with j / k, press space for details, and press ? to see all keyboard shortcuts.
```

## 輸出コンプライアンス

`ITSAppUsesNonExemptEncryption` を Info.plist で `NO` にしているので、ビルドごとの暗号の質問は出ない。
