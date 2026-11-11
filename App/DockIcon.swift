#if os(macOS)
import AppKit

/// 起動中の Dock のアイコンを今日の日付にする。終了すると固定のアイコンへ戻る（OS の仕様）。
@MainActor
enum DockIcon {
    /// いまの日付を描き、日付やタイムゾーンが変わるたびに描き直す。起動時に 1 回呼ぶ。
    static func start() {
        update()
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in update() }
            }
        }
    }

    private static func update(for date: Date = Date()) {
        guard let base = NSImage(named: "DockIconBase") else { return }
        let day = String(Calendar.autoupdatingCurrent.component(.day, from: date))
        let font = NSFont.systemFont(ofSize: side * 0.44, weight: .regular)
        let number = NSAttributedString(string: day, attributes: [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1),
        ])

        NSApp.applicationIconImage = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            base.draw(in: rect)
            number.draw(at: CGPoint(
                x: rect.midX - number.size().width / 2,
                y: side * bodyCenter - font.capHeight / 2 + font.descender
            ))
            return true
        }
    }

    private static let side: CGFloat = 512
    // 台紙（scripts/make-icon.swift の `--blank`）の、帯の下の余白の中心の高さ（下端からの割合）。
    // 1024px の台紙を上から見て、余白 100 + 帯 200 + 残りの紙 624 の半分 = 612
    private static let bodyCenter: CGFloat = 1 - 612.0 / 1024
}

/// ウインドウに依らず、アプリが動いている間ずっと Dock の日付を保つ（ウインドウを全部閉じてもアプリは終了しない）。
final class DockIconDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.start()
    }
}
#endif
