import DayoCore
import Foundation
import Observation

@MainActor
@Observable
final class TodayModel {
    private(set) var access: AccessStatus = .notDetermined
    private(set) var items: [TimelineItem] = []
    private(set) var errorMessage: String?

    private let source: CalendarSource
    private var isStarted = false

    init(source: CalendarSource) {
        self.source = source
    }

    /// 権限を要求し、許可されていれば今日の分を読み込んで変更を監視し続ける。
    /// Mac で複数ウィンドウが開いても監視は 1 本にする。
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        defer { isStarted = false }

        // 初回読み込み中に届く変更通知を取りこぼさないよう、先に購読を開始しておく。
        let changes = source.changes
        do {
            access = try await source.requestAccess()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // TODO: 拒否後にシステム設定で許可された場合の再確認はフェーズ2で扱う
        guard access == .granted else { return }
        await reload()
        for await _ in changes {
            await reload()
        }
    }

    func reload() async {
        guard let today = Calendar.autoupdatingCurrent.dateInterval(of: .day, for: .now) else { return }
        do {
            items = try await source.items(in: today).sorted(by: Self.timelineOrder)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 終日 → 時刻順 → 期日なし の順。同順位は id で安定させる。
    private static func timelineOrder(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
        switch (a.start, b.start) {
        case let (x?, y?):
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if x != y { return x < y }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return a.id < b.id
    }
}
