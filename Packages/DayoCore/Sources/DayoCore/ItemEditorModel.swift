import Foundation
import Observation

/// 詳細編集の状態。1 件の `TimelineItem` を開いて直し、`ItemDraft` にして保存する。
/// 新規登録にも使う。そのときは中身が空の仮の項目を持ち、保存で更新ではなく登録する。
@MainActor
@Observable
public final class ItemEditorModel {
    /// 繰り返しの選択肢。プリセットは開始日時の曜日・日から規則を作る。
    public enum RecurrenceOption: Hashable, CaseIterable, Sendable {
        case none
        case daily
        case weekdays
        case weekly
        case biweekly
        case monthly
        /// 元の規則がプリセットに無い（例: 毎週月水金）。変えなければそのまま保存する。
        case custom
        /// 年次・終了付きなど、このアプリで表せない規則。保存時に触らない。
        case unsupported
    }

    /// 編集中の項目。新規登録では仮の項目で、種別を切り替えると入れ替わる。
    public private(set) var item: TimelineItem
    /// まだ保存先に無い項目を作っているところか。
    public let isNew: Bool
    public var kind: ItemKind { item.kind }
    public var title: String
    /// メモ。Google カレンダーが足すビデオ会議の案内は除いてある（`conferenceURL` として出す）。
    public var notes: String
    /// event のみ。場所。ここでは直さず、地図を開くためだけに出す（保存時は元のまま）。
    public var location: String { item.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    /// 場所の最初の「,」より前（多くは施設の名前）。「,」が無い、または前後どちらかが空なら場所の全体。
    public var locationName: String { locationParts.name }
    /// 場所の最初の「,」より後ろ（多くは住所）。分けられなければ空。
    public var locationDetail: String { locationParts.detail }
    private var locationParts: (name: String, detail: String) {
        guard let comma = location.firstIndex(of: ",") else { return (location, "") }
        let name = location[..<comma].trimmingCharacters(in: .whitespaces)
        let detail = location[location.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return (location, "") }
        return (name, detail)
    }
    /// 場所を Google マップで検索する URL。場所が空なら nil。
    public var locationMapURL: URL? {
        guard !location.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: location)]
        // URLComponents は値の中の「+」をそのまま残す。受け側では空白と読まれるので、自分でエスケープする
        let encoded = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encoded
        return components?.url
    }
    /// event のみ。URL の欄の文字。空なら URL 無し。
    public var urlText: String
    /// 入力中の URL。空や URL として読めない文字なら nil。
    private var enteredURL: URL? {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }
    /// 入力中の URL のうち、ブラウザで開けるもの（http / https）。それ以外は開くボタンを出さない。
    public var linkURL: URL? {
        guard let url = enteredURL, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }
    /// メモに入っていたビデオ会議の参加用リンク。無ければ nil。
    public var conferenceURL: URL? { conference.url }
    private var conference: ConferenceNotes
    /// reminder のみ。false なら期日なし。event は常に true 扱い。
    public var hasDate: Bool
    public var isAllDay: Bool
    public var start: Date
    /// event のみ。
    public var end: Date
    public var recurrence: RecurrenceOption
    public var destinationID: String
    /// reminder のみ。
    public var priority: ReminderPriority
    /// reminder のみ。0 なら無し。
    public var earlyReminderMinutes: Int
    public private(set) var destinations: [Destination] = []
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// 保存に成功したあとに呼ぶ。タイムラインの再読み込みに使う。
    public var onChanged: (@MainActor () async -> Void)?
    /// 削除を任せる先。削除は取り消せるようタイムラインが実行を遅らせるので、ここでは取得元へ送らない。
    /// 受けられなかったら false を返す（別の保存の最中など）。
    public var onDelete: (@MainActor (TimelineItem, EditSpan) async -> Bool)?

    private let source: CalendarSource
    private let calendar: Calendar

    public convenience init(
        item: TimelineItem,
        source: CalendarSource,
        calendar: Calendar = QuickInputModel.defaultCalendar,
        now: Date = .now
    ) {
        self.init(item: item, isNew: false, source: source, calendar: calendar, now: now)
    }

    /// 新規登録用。`start` はその日時（終日ならその日）。予定は 1 時間で始める。
    public convenience init(
        newItemOf kind: ItemKind,
        start: Date,
        isAllDay: Bool,
        defaultEarlyReminderMinutes: Int = 0,
        source: CalendarSource,
        calendar: Calendar = QuickInputModel.defaultCalendar
    ) {
        let startValue = isAllDay ? calendar.startOfDay(for: start) : start
        let placeholder = Self.placeholder(
            kind: kind,
            start: startValue,
            end: isAllDay ? startValue : calendar.date(byAdding: .hour, value: 1, to: startValue) ?? startValue,
            isAllDay: isAllDay,
            earlyReminderMinutes: defaultEarlyReminderMinutes > 0 ? defaultEarlyReminderMinutes : nil
        )
        self.init(item: placeholder, isNew: true, source: source, calendar: calendar, now: start)
    }

    private init(item: TimelineItem, isNew: Bool, source: CalendarSource, calendar: Calendar, now: Date) {
        self.item = item
        self.isNew = isNew
        self.source = source
        self.calendar = calendar
        title = item.title
        urlText = item.url?.absoluteString ?? ""
        let conference = ConferenceNotes(item.notes ?? "")
        self.conference = conference
        notes = conference.body
        hasDate = item.start != nil
        // 期日なしから期日ありに切り替えたときの初期値は今日の 9:00
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let startValue = item.start ?? defaultStart
        start = startValue
        isAllDay = item.start == nil ? true : item.isAllDay
        end = item.end ?? calendar.date(byAdding: .hour, value: 1, to: startValue) ?? startValue
        destinationID = item.calendarIdentifier
        priority = item.priority
        earlyReminderMinutes = item.earlyReminderMinutes ?? 0
        recurrence = .none
        recurrence = Self.option(for: item, calendar: calendar)
    }

    /// 新規登録の仮の項目。保存先の識別子が空なので、選び直さなければ既定のカレンダー／リストに入る。
    private static func placeholder(
        kind: ItemKind, start: Date, end: Date, isAllDay: Bool, earlyReminderMinutes: Int?
    ) -> TimelineItem {
        TimelineItem(
            id: "new", calendarItemIdentifier: "", kind: kind, title: "", start: start,
            end: kind == .event ? end : nil, isAllDay: isAllDay, isCompleted: false,
            sourceName: "既定", accountName: "", color: TimelineItem.fallbackColor,
            recurrence: nil, earlyReminderMinutes: earlyReminderMinutes
        )
    }

    /// 新規登録で予定とリマインダーを切り替える。入力済みの内容は残し、保存先だけ既定に戻す
    /// （予定のカレンダーとリマインダーのリストは別物のため）。既存の項目の種別は変えられない。
    public func setKind(_ kind: ItemKind) async {
        guard isNew, kind != item.kind else { return }
        item = Self.placeholder(
            kind: kind, start: start, end: end, isAllDay: isAllDay, earlyReminderMinutes: item.earlyReminderMinutes
        )
        destinationID = ""
        await loadDestinations()
    }

    // MARK: - 繰り返し

    /// 画面に出す選択肢。custom / unsupported は元の項目がそうであるときだけ。
    public var recurrenceOptions: [RecurrenceOption] {
        var options: [RecurrenceOption] = [.none, .daily, .weekdays, .weekly, .biweekly, .monthly]
        let original = Self.option(for: item, calendar: calendar)
        if original == .custom || original == .unsupported {
            options.append(original)
        }
        return options
    }

    public func label(for option: RecurrenceOption) -> String {
        switch option {
        case .none: return "なし"
        case .daily: return "毎日"
        case .weekdays: return "平日"
        case .weekly: return preset(.weekly)?.localizedDescription ?? "毎週"
        case .biweekly: return preset(.biweekly)?.localizedDescription ?? "隔週"
        case .monthly: return preset(.monthly)?.localizedDescription ?? "毎月"
        case .custom: return item.recurrence?.localizedDescription ?? "カスタム"
        case .unsupported: return "カスタム（このアプリでは変更できません）"
        }
    }

    /// 選択肢と開始日時から規則を作る。`none` と `unsupported` は nil。
    private func preset(_ option: RecurrenceOption) -> RecurrenceSpec? {
        Self.preset(option, start: start, original: item.recurrence, calendar: calendar)
    }

    private static func preset(_ option: RecurrenceOption, start: Date, original: RecurrenceSpec?, calendar: Calendar) -> RecurrenceSpec? {
        let weekday = calendar.component(.weekday, from: start)
        switch option {
        case .none, .unsupported: return nil
        case .daily: return RecurrenceSpec(frequency: .daily)
        case .weekdays: return RecurrenceSpec(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])
        case .weekly: return RecurrenceSpec(frequency: .weekly, weekdays: [weekday])
        case .biweekly: return RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [weekday])
        case .monthly: return RecurrenceSpec(frequency: .monthly, daysOfMonth: [calendar.component(.day, from: start)])
        case .custom: return original
        }
    }

    /// 元の項目の規則に当たる選択肢。
    /// 曜日や日を省いた「毎週」「毎月」（純正アプリがよく作る形）は開始日時で補って比べる。
    static func option(for item: TimelineItem, calendar: Calendar) -> RecurrenceOption {
        guard item.hasRecurrence else { return .none }
        guard let spec = item.recurrence, let start = item.start else { return .unsupported }
        let normalized = normalize(spec, start: start, calendar: calendar)
        for option in [RecurrenceOption.daily, .weekdays, .weekly, .biweekly, .monthly]
        where preset(option, start: start, original: nil, calendar: calendar).map({ normalize($0, start: start, calendar: calendar) }) == normalized {
            return option
        }
        return .custom
    }

    /// 比較用に曜日・日の省略を補い、曜日の順序を揃える。
    private static func normalize(_ spec: RecurrenceSpec, start: Date, calendar: Calendar) -> RecurrenceSpec {
        var result = spec
        switch spec.frequency {
        case .weekly where spec.weekdays.isEmpty:
            result.weekdays = [calendar.component(.weekday, from: start)]
        case .monthly where spec.daysOfMonth.isEmpty && spec.weekOfMonth == nil:
            result.daysOfMonth = [calendar.component(.day, from: start)]
        default:
            break
        }
        result.weekdays.sort()
        return result
    }

    /// 選択肢と開始日が元のままなら元の規則をそのまま返す。Repository 側で「変更なし」と判定され、作り直しを避けられる。
    private var recurrenceForDraft: RecurrenceSpec? {
        let original = Self.option(for: item, calendar: calendar)
        if recurrence == original, let originalStart = item.start, let originalSpec = item.recurrence,
           calendar.isDate(originalStart, inSameDayAs: start) {
            return originalSpec
        }
        return preset(recurrence)
    }

    // MARK: - 保存

    /// 予定の繰り返しは回ごとに分けて変えられるので、保存・削除の前に範囲を聞く。
    public var needsSpanChoice: Bool {
        item.kind == .event && item.hasRecurrence
    }

    public var draft: ItemDraft {
        let usesDate = item.kind == .event || hasDate
        let startValue: Date? = usesDate ? (isAllDay ? calendar.startOfDay(for: start) : start) : nil
        var endValue: Date?
        if item.kind == .event {
            endValue = isAllDay ? calendar.startOfDay(for: end) : end
        }
        return ItemDraft(
            kind: item.kind,
            title: title.trimmingCharacters(in: .whitespaces),
            start: startValue,
            end: endValue,
            isAllDay: usesDate && isAllDay,
            recurrence: recurrenceForDraft,
            calendarID: destinationID.isEmpty ? nil : destinationID,
            notes: conference.combined(withBody: notes),
            location: item.kind == .event ? item.location : nil,
            url: item.kind == .event ? enteredURL : nil,
            priority: item.kind == .reminder ? priority : .none,
            // 時刻なしの期日は鳴る時刻が定まらないので付けない
            earlyReminderMinutes: item.kind == .reminder && usesDate && !isAllDay && earlyReminderMinutes > 0 ? earlyReminderMinutes : nil
        )
    }

    /// 保存できない理由。nil なら保存できる。
    public var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "タイトルを入力してください"
        }
        if item.kind == .event {
            let startValue = isAllDay ? calendar.startOfDay(for: start) : start
            let endValue = isAllDay ? calendar.startOfDay(for: end) : end
            // 開始と終了が同じ（長さ 0）の予定は EventKit 上あり得るので許す
            if endValue < startValue {
                return "終了は開始より前にはできません"
            }
        }
        if item.kind == .event, !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, enteredURL == nil {
            return "URL は https:// などから書いてください"
        }
        if item.kind == .reminder, !hasDate, recurrence != .none {
            return "繰り返しのあるリマインダーには期日が必要です"
        }
        return nil
    }

    /// 失敗しても候補が出ないだけなので、エラーは表示しない。
    public func loadDestinations() async {
        if let loaded = try? await source.destinations() {
            destinations = loaded.filter { $0.kind == item.kind }
        }
    }

    public func save(span: EditSpan = .thisOccurrence) async -> Bool {
        if let validationMessage {
            errorMessage = validationMessage
            return false
        }
        if isNew {
            return await perform { try await self.source.create(self.draft) }
        }
        return await perform { try await self.source.update(self.item, with: self.draft, span: span) }
    }

    public func delete(span: EditSpan = .thisOccurrence) async -> Bool {
        guard !isNew, !isSaving, let onDelete else { return false }
        guard await onDelete(item, span) else {
            errorMessage = "いまは削除できません。少し待ってから、もう一度試してください。"
            return false
        }
        errorMessage = nil
        return true
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        errorMessage = nil
        await onChanged?()
        return true
    }
}
