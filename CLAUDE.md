# Dayo

予定（Googleカレンダー）とTodo（iCloudリマインダー）を1本の時間軸で確認・入力できる、Mac + iPhone向けSwiftUIアプリ。

- 設計書: `docs/DESIGN.md`（判断に迷ったらまずここを読む）
- データは EventKit 経由で読み書きするだけ。独自サーバー・独自の永続化・通知処理は作らない
- EventKit への依存は `EventKitRepository`（`CalendarSource` protocol）に閉じ込め、画面は `TimelineItem` だけを扱う
- クイック入力は `protocol InputParser`。日本語パーサーは入力→期待結果のテーブルテストで育てる
- 最低対象OS: macOS 14 / iOS 17（`requestFullAccessToReminders` / `requestFullAccessToEvents` を使うため）
- MVPの範囲は設計書「スコープとMVP」に従う。範囲外の機能は提案に留め、勝手に実装しない
