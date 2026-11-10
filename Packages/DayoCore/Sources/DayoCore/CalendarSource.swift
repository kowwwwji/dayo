import EventKit
import Foundation

public enum AccessStatus: Hashable, Sendable {
    case granted
    case denied
    case restricted
    case notDetermined
}

extension AccessStatus {
    /// 予定とリマインダー両方の権限状態を1つにまとめる。表示には両方のフルアクセスが要る。
    public init(events: EKAuthorizationStatus, reminders: EKAuthorizationStatus) {
        let both = [events, reminders]
        if both.contains(.restricted) {
            self = .restricted
        } else if both.contains(.notDetermined) {
            self = .notDetermined
        } else if both.allSatisfy({ $0 == .fullAccess }) {
            self = .granted
        } else {
            self = .denied
        }
    }
}

public enum CalendarSourceError: LocalizedError, Equatable {
    /// 取得元に該当する項目が無い（他端末で削除された等）。
    case itemNotFound
    /// リマインダーにしか使えない操作を予定に対して行った。
    case notAReminder
    /// 予定には開始日時が要る。
    case eventNeedsStart
    /// 保存先のカレンダー／リストが無い（アカウント未設定など）。
    case noCalendar

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: "項目が見つかりません。他の端末で削除された可能性があります。"
        case .notAReminder: "この操作はリマインダーにしか使えません。"
        case .eventNeedsStart: "予定には日時が必要です。"
        case .noCalendar: "保存先のカレンダーまたはリストがありません。"
        }
    }
}

/// 1 回の取得結果。`items` は期間に属するもの、`overdue` は期間より前に期日が過ぎた未完了リマインダー。
public struct TimelineSnapshot: Equatable {
    public var items: [TimelineItem]
    public var overdue: [TimelineItem]

    public init(items: [TimelineItem], overdue: [TimelineItem]) {
        self.items = items
        self.overdue = overdue
    }

    public static let empty = TimelineSnapshot(items: [], overdue: [])
}

/// 予定・リマインダーの取得元。画面はこの protocol と TimelineItem だけを扱う。
public protocol CalendarSource {
    /// 予定とリマインダーの権限をまとめて要求し、結果の状態を返す。
    func requestAccess() async throws -> AccessStatus
    /// 期間に属する予定・リマインダー（`TimelineItem.falls(in:)` の規則）を 1 回の取得で返す。
    /// `includingOverdue` なら期間より前に期日が過ぎた未完了リマインダーも `overdue` に入れる。
    func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot
    /// リマインダーの完了状態を変える。反映は呼び出し側で再取得する。
    func setCompleted(_ completed: Bool, for item: TimelineItem) async throws
    /// 予定またはリマインダーを新規登録する。反映は `changes` 経由か呼び出し側の再取得で行う。
    func create(_ draft: ItemDraft) async throws
    /// 取得元に変更があったときに値を流す。受け取ったら表示中の期間を再取得する。
    var changes: AsyncStream<Void> { get }
}
