import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private let now = date(2026, 11, 12, 10)

private func item(
    kind: ItemKind = .event,
    start: Date? = date(2026, 11, 11, 17, 30),
    end: Date? = nil,
    isAllDay: Bool = false,
    recurrence: RecurrenceSpec? = nil,
    hasRecurrence: Bool? = nil,
    notes: String? = nil,
    location: String? = nil,
    url: URL? = nil
) -> TimelineItem {
    TimelineItem(
        id: "x", calendarItemIdentifier: "x", kind: kind, title: "MTG", start: start, end: end,
        isAllDay: isAllDay, isCompleted: false, sourceName: "個人的", accountName: "",
        color: CGColor(gray: 0, alpha: 1), recurrence: recurrence, hasRecurrence: hasRecurrence,
        notes: notes, location: location, url: url
    )
}

private func summary(_ item: TimelineItem) -> ItemSummary {
    ItemSummary(item, calendar: tokyo, now: now)
}

@Suite struct ItemSummaryTests {
    // MARK: - 日時

    @Test(arguments: [
        // 予定
        (ItemKind.event, date(2026, 11, 11, 17, 30), date(2026, 11, 11, 18, 30), false, "11/11 (水) 17:30–18:30"),
        (.event, date(2026, 11, 11, 9, 5), date(2026, 11, 11, 10, 0), false, "11/11 (水) 9:05–10:00"),
        // 長さの無い予定は開始だけ
        (.event, date(2026, 11, 11, 17, 30), date(2026, 11, 11, 17, 30), false, "11/11 (水) 17:30"),
        // 日をまたぐ予定は終わりにも日付を書く
        (.event, date(2026, 11, 11, 22, 0), date(2026, 11, 12, 1, 0), false, "11/11 (水) 22:00 – 11/12 (木) 1:00"),
        // 0:00 ちょうどに終わる予定は、その日のうちに終わったものとして書く
        (.event, date(2026, 11, 11, 22, 0), date(2026, 11, 12, 0, 0), false, "11/11 (水) 22:00–24:00"),
        // 終日
        (.event, date(2026, 11, 11), date(2026, 11, 11, 23, 59), true, "11/11 (水)"),
        (.event, date(2026, 11, 11), date(2026, 11, 12), true, "11/11 (水)"),
        (.event, date(2026, 11, 11), date(2026, 11, 13, 23, 59), true, "11/11 (水) – 11/13 (金)"),
        (.event, date(2026, 11, 11), date(2026, 11, 14), true, "11/11 (水) – 11/13 (金)"),
        // 今年でない日は年から書く
        (.event, date(2027, 1, 31, 10, 0), date(2027, 1, 31, 11, 0), false, "2027/1/31 (日) 10:00–11:00"),
        (.event, date(2026, 12, 31), date(2027, 1, 1, 23, 59), true, "12/31 (木) – 2027/1/1 (金)"),
        // リマインダー
        (.reminder, date(2026, 11, 11, 17, 30), nil, false, "11/11 (水) 17:30"),
        (.reminder, date(2026, 11, 11), nil, true, "11/11 (水)"),
    ] as [(ItemKind, Date, Date?, Bool, String)])
    func theDateLineIsWrittenForEachShape(kind: ItemKind, start: Date, end: Date?, isAllDay: Bool, expected: String) {
        #expect(summary(item(kind: kind, start: start, end: end, isAllDay: isAllDay)).dateText == expected)
    }

    @Test func anUndatedReminderHasNoDateLine() {
        #expect(summary(item(kind: .reminder, start: nil)).dateText == nil)
    }

    // MARK: - 繰り返し

    @Test func aPlainItemHasNoRecurrenceLine() {
        #expect(summary(item()).recurrenceText == nil)
    }

    @Test func theRecurrenceLineDescribesTheRule() {
        let rule = RecurrenceSpec(frequency: .weekly, weekdays: [2, 4])
        #expect(summary(item(recurrence: rule)).recurrenceText == "毎週月水曜")
    }

    /// 純正アプリは曜日や日を省いた「毎週」「毎月」を作る。開始日時で補って書く（編集ポップオーバーの選択肢と同じ）。
    @Test func aRuleWithoutItsDayIsFilledFromTheStart() {
        #expect(summary(item(recurrence: RecurrenceSpec(frequency: .weekly))).recurrenceText == "毎週水曜")
        #expect(summary(item(recurrence: RecurrenceSpec(frequency: .monthly))).recurrenceText == "毎月11日")
    }

    @Test func aRuleThisAppCannotExpressIsOnlyAnnounced() {
        #expect(summary(item(hasRecurrence: true)).recurrenceText == "繰り返しあり")
    }

    // MARK: - 場所

    @Test func theLocationIsTrimmedAndLinkedToTheMap() {
        let result = summary(item(location: "  会議室 A \n"))
        #expect(result.location == "会議室 A")
        #expect(result.locationMapURL?.absoluteString == "https://www.google.com/maps/search/?api=1&query=%E4%BC%9A%E8%AD%B0%E5%AE%A4%20A")
    }

    @Test func anEmptyLocationGivesNoLine() {
        #expect(summary(item(location: "   ")).location == nil)
        #expect(summary(item(location: "   ")).locationMapURL == nil)
        #expect(summary(item()).location == nil)
    }

    @Test func theMapQueryKeepsItsSeparatorsInsideTheLocation() {
        let url = summary(item(location: "東京駅 丸の内口&q=x+y")).locationMapURL
        let query = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        #expect(query == "api=1&query=%E6%9D%B1%E4%BA%AC%E9%A7%85%20%E4%B8%B8%E3%81%AE%E5%86%85%E5%8F%A3%26q%3Dx%2By")
    }

    // MARK: - URL

    @Test(arguments: [
        ("https://example.com/a", true),
        ("http://example.com", true),
        ("mailto:a@example.com", false),
        ("file:///etc/passwd", false),
        ("https:", false),
    ])
    func onlyAWebLinkIsOffered(text: String, offered: Bool) {
        #expect((summary(item(url: URL(string: text))).linkURL != nil) == offered)
    }

    // MARK: - メモとビデオ会議

    private static let separator = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"

    private static func invitation(_ link: String) -> String {
        "\(separator)\nGoogle Meet に参加: \(link)\nこのセクションは編集しないでください。\n\(separator)"
    }

    @Test func theMeetingBlockLeavesTheNotesAndBecomesALink() {
        let result = summary(item(notes: "議題: 来期の計画\n\n" + Self.invitation("https://meet.google.com/abc-defg-hij")))
        #expect(result.notes == "議題: 来期の計画")
        #expect(result.conferenceURL?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func aBlockPointingElsewhereStaysInTheNotes() {
        let notes = "議題\n\n" + Self.invitation("https://evil.example.com/join")
        let result = summary(item(notes: notes))
        #expect(result.notes == notes)
        #expect(result.conferenceURL == nil)
    }

    @Test func emptyNotesGiveNoLine() {
        #expect(summary(item()).notes == nil)
        #expect(summary(item(notes: " \n ")).notes == nil)
        // 案内だけのメモ
        #expect(summary(item(notes: Self.invitation("https://meet.google.com/abc-defg-hij"))).notes == nil)
    }

    @Test func notesAreTrimmedAtBothEnds() {
        #expect(summary(item(notes: "\n1 行目\n2 行目\n\n")).notes == "1 行目\n2 行目")
    }
}
