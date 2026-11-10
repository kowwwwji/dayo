import Foundation

/// 登録・更新に渡す 1 件分。`CalendarSource.create` / `update` の入力。
public struct ItemDraft: Equatable {
    public var kind: ItemKind
    public var title: String
    /// event: 開始 / reminder: 期日。期日なしは nil。
    public var start: Date?
    /// event のみ。
    public var end: Date?
    public var isAllDay: Bool
    public var recurrence: RecurrenceSpec?
    /// 保存先をリスト名／カレンダー名の前方一致で選ぶ（クイック入力）。nil なら既定。
    public var listName: String?
    /// 保存先を識別子で選ぶ（エディタ）。あれば `listName` より優先。
    public var calendarID: String?
    public var notes: String?
    /// reminder のみ。
    public var priority: ReminderPriority

    public init(
        kind: ItemKind,
        title: String,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        recurrence: RecurrenceSpec? = nil,
        listName: String? = nil,
        calendarID: String? = nil,
        notes: String? = nil,
        priority: ReminderPriority = .none
    ) {
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.listName = listName
        self.calendarID = calendarID
        self.notes = notes
        self.priority = priority
    }
}
