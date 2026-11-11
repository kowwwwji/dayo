import SwiftUI

#if os(macOS)
import AppKit

/// 起動中の Dock のアイコンを今日の日付にする。終了すると固定のアイコンへ戻る（OS の仕様）。
@MainActor
enum DockIcon {
    static func update(for date: Date = Date()) {
        guard let base = NSImage(named: "DockIconBase") else { return }
        let day = String(Calendar.current.component(.day, from: date))
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
    // 台紙（scripts/make-icon.swift の `--blank`）の、帯の下の余白の中心の高さ（下端からの割合）
    private static let bodyCenter: CGFloat = 1 - 612.0 / 1024
}

extension View {
    /// このビューが出ている間、Dock のアイコンを今日の日付に保つ。
    func showsTodayInDock() -> some View {
        self
            .task { DockIcon.update() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                DockIcon.update()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)
            ) { _ in
                DockIcon.update()
            }
    }
}
#endif
