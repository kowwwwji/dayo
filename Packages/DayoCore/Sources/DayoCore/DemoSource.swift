#if DEBUG
import CoreGraphics
import Foundation

/// 架空の予定とリマインダーを返す取得元。App Store のスクリーンショットを、実際の予定を写さずに撮るために使う。
/// EventKit には触れず、変更はメモリの中だけで起きる（終了すれば元に戻る）。提出するビルドに入らないよう DEBUG だけ。
///
/// 中身は曜日ごとの決まった並びで、日を表示したときに作る。今日より前の日のリマインダーは完了済みにし、
/// 期日が過ぎた未完了のリマインダーは昨日の 1 件だけにする。
public final class DemoSource: CalendarSource {
    private let calendar: Calendar
    private let now: () -> Date
    private var items: [String: TimelineItem] = [:]
    private var generatedDays: Set<Date> = []
    private var nextID = 0

    public init(calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = { .now }) {
        self.calendar = calendar
        self.now = now
        for (title, list) in Self.undated {
            add(kind: .reminder, title: title, start: nil, end: nil, isAllDay: false, in: list)
        }
        let today = calendar.startOfDay(for: now())
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            add(kind: .reminder, title: "市役所に書類を出す", start: time(17, 0, on: yesterday), end: nil, isAllDay: false,
                in: Self.reminders)
        }
    }

    public func requestAccess() async throws -> AccessStatus { .granted }

    public func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot {
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            generate(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let all = items.values.sorted { ($0.start ?? .distantPast, $0.id) < ($1.start ?? .distantPast, $1.id) }
        return TimelineSnapshot(
            items: all.filter { $0.falls(in: range) },
            overdue: includingOverdue
                ? all.filter { $0.kind == .reminder && !$0.isCompleted && ($0.start.map { $0 < range.start } ?? false) }
                : [],
            undated: all.filter { $0.kind == .reminder && $0.start == nil && !$0.isCompleted }
        )
    }

    public func setCompleted(_ completed: Bool, for item: TimelineItem) async throws {
        guard item.kind == .reminder else { throw CalendarSourceError.notAReminder }
        guard items[item.calendarItemIdentifier] != nil else { throw CalendarSourceError.itemNotFound }
        items[item.calendarItemIdentifier]?.isCompleted = completed
        announce()
    }

    public func create(_ draft: ItemDraft) async throws {
        if draft.kind == .event, draft.start == nil { throw CalendarSourceError.eventNeedsStart }
        let list = try destination(for: draft) ?? (draft.kind == .event ? Self.work : Self.reminders)
        let id = add(kind: draft.kind, title: draft.title, start: draft.start, end: draft.end,
                     isAllDay: draft.isAllDay, in: list)
        apply(draft, to: id)
        announce()
    }

    public func update(_ item: TimelineItem, with draft: ItemDraft, span: EditSpan) async throws {
        guard var stored = items[item.calendarItemIdentifier] else { throw CalendarSourceError.itemNotFound }
        if draft.kind == .event, draft.start == nil { throw CalendarSourceError.eventNeedsStart }
        if let list = try destination(for: draft) {
            stored.sourceName = list.name
            stored.color = list.color
            stored.calendarIdentifier = list.id
        }
        stored.title = draft.title
        stored.start = draft.start
        stored.end = draft.kind == .event ? draft.end : nil
        stored.isAllDay = draft.isAllDay
        items[item.calendarItemIdentifier] = stored
        apply(draft, to: item.calendarItemIdentifier)
        announce()
    }

    public func delete(_ item: TimelineItem, span: EditSpan) async throws {
        guard items.removeValue(forKey: item.calendarItemIdentifier) != nil else {
            throw CalendarSourceError.itemNotFound
        }
        announce()
    }

    public func destinations() async throws -> [Destination] {
        Self.lists.map { Destination(id: $0.id, name: $0.name, kind: $0.kind, color: $0.color) }
    }

    public func calendars() async throws -> [CalendarInfo] {
        Self.lists.map {
            CalendarInfo(id: $0.id, name: $0.name, kind: $0.kind, color: $0.color, accountName: $0.accountName)
        }
    }

    /// EventKit と同じく、変更は通知で伝える（読む側ごとにストリームを作る）。
    public var changes: AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let token = NotificationCenter.default.addObserver(forName: Self.changed, object: self, queue: nil) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    // MARK: - 中身

    private struct List {
        var id: String
        var name: String
        var kind: ItemKind
        var color: CGColor
        var accountName: String
    }

    private static let work = List(id: "demo-work", name: "仕事", kind: .event,
                                   color: CGColor(srgbRed: 0.22, green: 0.48, blue: 0.95, alpha: 1), accountName: "Google")
    private static let personal = List(id: "demo-personal", name: "個人", kind: .event,
                                       color: CGColor(srgbRed: 0.20, green: 0.68, blue: 0.36, alpha: 1), accountName: "Google")
    private static let family = List(id: "demo-family", name: "家族", kind: .event,
                                     color: CGColor(srgbRed: 0.98, green: 0.56, blue: 0.12, alpha: 1), accountName: "Google")
    private static let reminders = List(id: "demo-reminders", name: "リマインダー", kind: .reminder,
                                        color: CGColor(srgbRed: 0.62, green: 0.38, blue: 0.90, alpha: 1), accountName: "iCloud")
    private static let shopping = List(id: "demo-shopping", name: "買い物", kind: .reminder,
                                       color: CGColor(srgbRed: 0.90, green: 0.33, blue: 0.40, alpha: 1), accountName: "iCloud")
    private static let lists = [work, personal, family, reminders, shopping]

    private static let undated: [(String, List)] = [
        ("本棚を組み立てる", reminders),
        ("夏休みの宿を探す", reminders),
        ("電池（単 3）", shopping),
    ]

    /// 1 日分の並び。時刻は (時, 分)、予定の長さは分。
    private enum Entry {
        case event(String, List, at: (Int, Int), minutes: Int, location: String? = nil, notes: String? = nil)
        case allDay(String, List)
        case reminder(String, List, at: (Int, Int), priority: ReminderPriority = .none)
    }

    /// `weekday` は 1 = 日曜 … 7 = 土曜（`Calendar.component(.weekday)` と同じ）。
    private static func entries(weekday: Int) -> [Entry] {
        let standup = Entry.event("朝会", work, at: (9, 30), minutes: 15)
        switch weekday {
        case 2:
            return [standup,
                    .event("週次定例", work, at: (10, 0), minutes: 60, location: "会議室 A"),
                    .event("ランチ", personal, at: (12, 0), minutes: 60),
                    .event("見積もりの確認", work, at: (15, 0), minutes: 30),
                    .reminder("経費を精算する", reminders, at: (17, 0))]
        case 3:
            return [standup,
                    .event("デザインレビュー", work, at: (14, 0), minutes: 90, location: "会議室 B",
                           notes: "新しい画面の案を 3 つ見比べる"),
                    .reminder("牛乳とパン", shopping, at: (18, 30)),
                    .event("英会話", personal, at: (20, 0), minutes: 60)]
        case 4:
            return [standup,
                    .reminder("資料を送る", reminders, at: (11, 0), priority: .high),
                    .event("1on1", work, at: (13, 0), minutes: 30),
                    .event("企画の打ち合わせ", work, at: (15, 30), minutes: 60, location: "オンライン"),
                    .event("ヨガ", personal, at: (19, 0), minutes: 60)]
        case 5:
            return [standup,
                    .event("採用面接", work, at: (11, 0), minutes: 60),
                    .event("歯医者", personal, at: (16, 30), minutes: 45),
                    .reminder("ゴミ出し", reminders, at: (21, 0))]
        case 6:
            return [.allDay("給料日", personal),
                    standup,
                    .reminder("週報を書く", reminders, at: (16, 0)),
                    .event("チームの食事会", work, at: (18, 30), minutes: 120, location: "駅前の居酒屋")]
        case 7:
            return [.event("子どもの水泳教室", family, at: (10, 0), minutes: 90),
                    .reminder("クリーニングを受け取る", reminders, at: (14, 0)),
                    .event("買い出し", family, at: (16, 0), minutes: 60)]
        default:
            return [.allDay("おばあちゃんの誕生日", family),
                    .event("ジョギング", personal, at: (8, 0), minutes: 45),
                    .event("映画", family, at: (14, 0), minutes: 120),
                    .reminder("植木に水をやる", reminders, at: (19, 0))]
        }
    }

    private func generate(_ day: Date) {
        guard generatedDays.insert(day).inserted else { return }
        let isPast = day < calendar.startOfDay(for: now())
        for entry in Self.entries(weekday: calendar.component(.weekday, from: day)) {
            switch entry {
            case let .event(title, list, at, minutes, location, notes):
                let start = time(at.0, at.1, on: day)
                let id = add(kind: .event, title: title, start: start,
                             end: calendar.date(byAdding: .minute, value: minutes, to: start), isAllDay: false, in: list)
                items[id]?.location = location
                items[id]?.notes = notes
            case let .allDay(title, list):
                add(kind: .event, title: title, start: day, end: calendar.date(byAdding: .day, value: 1, to: day),
                    isAllDay: true, in: list)
            case let .reminder(title, list, at, priority):
                let id = add(kind: .reminder, title: title, start: time(at.0, at.1, on: day), end: nil,
                             isAllDay: false, in: list)
                items[id]?.priority = priority
                items[id]?.isCompleted = isPast
            }
        }
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// 識別子は画面の id と EventKit の識別子を兼ねる（繰り返しを作らないので回ごとに分けなくてよい）。
    @discardableResult
    private func add(kind: ItemKind, title: String, start: Date?, end: Date?, isAllDay: Bool, in list: List) -> String {
        nextID += 1
        let id = "demo-item-\(nextID)"
        items[id] = TimelineItem(
            id: id, calendarItemIdentifier: id, kind: kind, title: title, start: start,
            end: kind == .event ? end : nil, isAllDay: isAllDay, isCompleted: false,
            sourceName: list.name, accountName: list.accountName, color: list.color, recurrence: nil,
            calendarIdentifier: list.id
        )
        return id
    }

    /// 日時と保存先以外の欄を写す。
    private func apply(_ draft: ItemDraft, to id: String) {
        items[id]?.notes = draft.notes
        items[id]?.location = draft.kind == .event ? draft.location : nil
        items[id]?.url = draft.url
        items[id]?.priority = draft.kind == .reminder ? draft.priority : .none
        items[id]?.earlyReminderMinutes = draft.kind == .reminder ? draft.earlyReminderMinutes : nil
    }

    /// `EventKitRepository` と同じ決め方: 識別子、無ければ名前。名前があるのに見つからなければエラー。
    private func destination(for draft: ItemDraft) throws -> List? {
        let candidates = Self.lists.filter { $0.kind == draft.kind }
        if let id = draft.calendarID {
            guard let found = candidates.first(where: { $0.id == id }) else { throw CalendarSourceError.noCalendar }
            return found
        }
        guard let name = draft.listName, !name.isEmpty else { return nil }
        guard let found = EventKitRepository.match(name, in: candidates, title: \.name) else {
            throw CalendarSourceError.listNotFound(name)
        }
        return found
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    private static let changed = Notification.Name("DemoSourceChanged")
}
#endif
