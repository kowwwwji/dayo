#if os(macOS)
import AppKit
import DayoCore

/// ウインドウに依らない、アプリ全体の起動と終了の処理（ウインドウを全部閉じてもアプリは終了しない）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 終了時に保留の削除を実行する相手。`DayoApp` が起動時に入れる。
    @MainActor static var timeline: TimelineModel?

    /// アプリが動いている間ずっと Dock の日付を保つ。
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.start()
    }

    /// 取り消せるよう保留にしている削除を、終了の前に実行する。実行しないと、消したはずの項目が残る。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let timeline = Self.timeline, timeline.pendingDeletion != nil else { return .terminateNow }
        Task { @MainActor in
            await timeline.flushPendingDeletion()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
