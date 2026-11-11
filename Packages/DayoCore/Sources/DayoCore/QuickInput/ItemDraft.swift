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
    /// event のみ。
    public var location: String?
    /// event のみ。
    public var url: URL?
    /// reminder のみ。
    public var priority: ReminderPriority
    /// reminder のみ。期日の何分前に通知するか。nil なら無し。
    public var earlyReminderMinutes: Int?

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
        location: String? = nil,
        url: URL? = nil,
        priority: ReminderPriority = .none,
        earlyReminderMinutes: Int? = nil
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
        self.location = location
        self.url = url
        self.priority = priority
        self.earlyReminderMinutes = earlyReminderMinutes
    }
}

extension ItemDraft {
    /// 項目を同じ長さのまま新しい開始へ動かす下書き。他の属性は元のまま。
    /// 保存先は変えないので `calendarID` は nil。繰り返しは元の規則を渡し、Repository 側で「変更なし」と判定させる。
    public init(moving item: TimelineItem, to start: Date, isAllDay: Bool = false) {
        let duration = item.start.flatMap { oldStart in item.end.map { $0.timeIntervalSince(oldStart) } } ?? 0
        self.init(item, start: start, end: start.addingTimeInterval(max(0, duration)), isAllDay: isAllDay)
    }

    /// 終日の項目を時刻付きにする下書き。予定は 1 時間（終日の長さは時間軸に持ち込めないため）、リマインダーは期日だけ。
    public init(scheduling item: TimelineItem, at start: Date) {
        self.init(item, start: start, end: start.addingTimeInterval(3600), isAllDay: false)
    }

    /// 時刻付きの項目を、その日の終日にする下書き。`day` はその日の 0:00。
    public init(makingAllDay item: TimelineItem, on day: Date) {
        self.init(item, start: day, end: day, isAllDay: true)
    }

    /// 日時だけを差し替える。`end` は予定のときだけ使う。
    private init(_ item: TimelineItem, start: Date, end: Date, isAllDay: Bool) {
        self.init(
            kind: item.kind,
            title: item.title,
            start: start,
            end: item.kind == .event ? end : nil,
            isAllDay: isAllDay,
            recurrence: item.recurrence,
            notes: item.notes,
            location: item.location,
            url: item.url,
            priority: item.priority,
            // 時刻なしの期日は鳴る時刻が定まらないので付けない
            earlyReminderMinutes: isAllDay ? nil : item.earlyReminderMinutes
        )
    }
}
