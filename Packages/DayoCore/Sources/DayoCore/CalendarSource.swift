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
    /// `#名前` に一致するリスト／カレンダーが無い。
    case listNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: "項目が見つかりません。他の端末で削除された可能性があります。"
        case .notAReminder: "この操作はリマインダーにしか使えません。"
        case .eventNeedsStart: "予定には日時が必要です。"
        case .noCalendar: "保存先のカレンダーまたはリストがありません。"
        case .listNotFound(let name): "「\(name)」というリストやカレンダーはありません。"
        }
    }
}

/// 1 回の取得結果。`items` は期間に属するもの、`overdue` は期間より前に期日が過ぎた未完了リマインダー、
/// `recurring` は将来回を展開する元（`VirtualOccurrences.sources`）。
public struct TimelineSnapshot: Equatable {
    public var items: [TimelineItem]
    public var overdue: [TimelineItem]
    public var recurring: [TimelineItem]

    public init(items: [TimelineItem], overdue: [TimelineItem], recurring: [TimelineItem] = []) {
        self.items = items
        self.overdue = overdue
        self.recurring = recurring
    }

    public static let empty = TimelineSnapshot(items: [], overdue: [])
}

/// 繰り返し予定の編集・削除がどの回に及ぶか。
/// リマインダーの繰り返しは 1 オブジェクトしか無いので常に全体が変わり、この値は無視される。
public enum EditSpan: Equatable, Sendable {
    case thisOccurrence
    case futureOccurrences
}

/// 保存先の候補。リマインダーのリストか予定のカレンダー。
public struct Destination: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ItemKind
    public var color: CGColor

    public init(id: String, name: String, kind: ItemKind, color: CGColor) {
        self.id = id
        self.name = name
        self.kind = kind
        self.color = color
    }
}

/// 予定・リマインダーの取得元。画面はこの protocol と TimelineItem だけを扱う。
public protocol CalendarSource {
    /// 予定とリマインダーの権限をまとめて要求し、結果の状態を返す。
    func requestAccess() async throws -> AccessStatus
    /// 期間に属する予定・リマインダー（`TimelineItem.falls(in:)` の規則）を 1 回の取得で返す。
    /// `includingOverdue` なら期間より前に期日が過ぎた未完了リマインダーも `overdue` に入れる。
    /// `recurring` は常に入れる。
    func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot
    /// リマインダーの完了状態を変える。反映は呼び出し側で再取得する。
    func setCompleted(_ completed: Bool, for item: TimelineItem) async throws
    /// 予定またはリマインダーを新規登録する。反映は `changes` 経由か呼び出し側の再取得で行う。
    func create(_ draft: ItemDraft) async throws
    /// 既存の項目を `draft` の内容で上書きする。種別（event / reminder）は変えられない。
    func update(_ item: TimelineItem, with draft: ItemDraft, span: EditSpan) async throws
    func delete(_ item: TimelineItem, span: EditSpan) async throws
    /// 書き込めるリストとカレンダーの一覧。クイック入力の `#` `@` 補完とエディタの保存先選択に使う。
    func destinations() async throws -> [Destination]
    /// 取得元に変更があったときに値を流す。受け取ったら表示中の期間を再取得する。
    var changes: AsyncStream<Void> { get }
}
