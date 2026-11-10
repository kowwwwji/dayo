import CoreGraphics
import Foundation

public enum ItemKind: Hashable, Sendable {
    case event
    case reminder
}

/// 予定とリマインダーを画面向けに統一した表現。永続化はしない（正は EventKit 側）。
/// EventKit の型は持たず、Repository で変換する。
public struct TimelineItem: Identifiable, Equatable {
    /// 画面上の一意キー。繰り返し予定は回ごとに異なる値になる。
    public let id: String
    /// EventKit から元のオブジェクトを引き直すためのキー（繰り返し予定では全回で共通）。
    public let calendarItemIdentifier: String
    public let kind: ItemKind
    public var title: String
    /// event: startDate / reminder: dueDate。期日なしリマインダーは nil。
    public var start: Date?
    /// event のみ。
    public var end: Date?
    public var isAllDay: Bool
    /// reminder のみ。event は常に false。
    public var isCompleted: Bool
    /// リスト名 or カレンダー名。
    public var sourceName: String
    /// アカウント名（iCloud / Google など）。同名カレンダーの区別と接続確認に使う。
    public var accountName: String
    public var color: CGColor
    /// このアプリで編集できる形の繰り返し。表せない規則（年次・終了付きなど）は nil で `hasRecurrence` だけ true。
    public var recurrence: RecurrenceSpec?
    /// 何らかの繰り返し規則を持つか。`recurrence == nil` でも true ならカスタム規則。
    public var hasRecurrence: Bool
    /// 共有リストか。
    public var isShared: Bool
    public var notes: String?
    /// 保存先のリスト／カレンダーの識別子（`Destination.id` と同じ）。
    public var calendarIdentifier: String
    /// 保存先が書き込み可能か。誕生日・祝日・購読カレンダーは false。
    public var isEditable: Bool
    /// reminder のみ。event は常に none。
    public var priority: ReminderPriority
    /// reminder のみ。期日の何分前に通知するか（早期リマインダー）。無ければ nil。
    public var earlyReminderMinutes: Int?
    /// 繰り返しリマインダーの将来回を画面用に展開したもの。EventKit には実体が無いので操作できない。
    public var isVirtual: Bool

    /// このアプリで表せない繰り返し規則を持つ。編集時に規則へ触らない。
    public var hasCustomRecurrence: Bool { hasRecurrence && recurrence == nil }

    public init(
        id: String,
        calendarItemIdentifier: String,
        kind: ItemKind,
        title: String,
        start: Date?,
        end: Date?,
        isAllDay: Bool,
        isCompleted: Bool,
        sourceName: String,
        accountName: String,
        color: CGColor,
        recurrence: RecurrenceSpec?,
        isShared: Bool,
        hasRecurrence: Bool? = nil,
        notes: String? = nil,
        calendarIdentifier: String = "",
        isEditable: Bool = true,
        priority: ReminderPriority = .none,
        earlyReminderMinutes: Int? = nil,
        isVirtual: Bool = false
    ) {
        self.id = id
        self.calendarItemIdentifier = calendarItemIdentifier
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCompleted = isCompleted
        self.sourceName = sourceName
        self.accountName = accountName
        self.color = color
        self.recurrence = recurrence
        self.hasRecurrence = hasRecurrence ?? (recurrence != nil)
        self.isShared = isShared
        self.notes = notes
        self.calendarIdentifier = calendarIdentifier
        self.isEditable = isEditable
        self.priority = priority
        self.earlyReminderMinutes = earlyReminderMinutes
        self.isVirtual = isVirtual
    }

    /// 期間の日に表示すべきか。期日で判定し、期日なしのリマインダーは時間軸に載せない。
    /// `range.end`（翌日 0:00）は含めない。
    public func falls(in range: DateInterval) -> Bool {
        guard let start else { return false }
        return start >= range.start && start < range.end
    }
}
