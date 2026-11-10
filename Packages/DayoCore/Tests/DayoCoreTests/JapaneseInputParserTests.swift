import Foundation
import Testing
@testable import DayoCore

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    calendar.locale = Locale(identifier: "ja_JP")
    return calendar
}()

/// 2026-11-10（火）10:00 JST。
private let reference = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!

private func ymd(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
    DateComponents(year: year, month: month, day: day)
}

private func hm(_ hour: Int, _ minute: Int = 0) -> DateComponents {
    DateComponents(hour: hour, minute: minute)
}

private func parse(_ text: String) -> ParsedInput {
    JapaneseInputParser().parse(text, reference: reference, calendar: tokyo)
}

@Suite struct JapaneseInputParserTests {
    @Test(arguments: [
        // 設計書の入力例
        ("毎週月曜 9時 ゴミ出し #家族",
         ParsedInput(title: "ゴミ出し", time: hm(9), recurrence: .init(frequency: .weekly, weekdays: [2]), listName: "家族")),
        ("毎月最終金曜 経費精算",
         ParsedInput(title: "経費精算", recurrence: .init(frequency: .monthly, weekdays: [6], weekOfMonth: -1))),
        ("明日 15時 歯医者",
         ParsedInput(title: "歯医者", date: ymd(2026, 11, 11), time: hm(15))),
        ("金曜 10時-11時 面談 @予定",
         ParsedInput(title: "面談", kind: .event, date: ymd(2026, 11, 13), time: hm(10), endTime: hm(11))),
        ("牛乳買う",
         ParsedInput(title: "牛乳買う")),
        // 繰り返し
        ("毎日 朝 ストレッチ",
         ParsedInput(title: "ストレッチ", time: hm(8), recurrence: .init(frequency: .daily))),
        ("平日 9:30 朝会",
         ParsedInput(title: "朝会", time: hm(9, 30), recurrence: .init(frequency: .weekly, weekdays: [2, 3, 4, 5, 6]))),
        ("毎週月水金 ジム",
         ParsedInput(title: "ジム", recurrence: .init(frequency: .weekly, weekdays: [2, 4, 6]))),
        ("隔週火曜 資源ごみ",
         ParsedInput(title: "資源ごみ", recurrence: .init(frequency: .weekly, interval: 2, weekdays: [3]))),
        ("毎月15日 家賃",
         ParsedInput(title: "家賃", recurrence: .init(frequency: .monthly, daysOfMonth: [15]))),
        ("毎月第2火曜 定例",
         ParsedInput(title: "定例", recurrence: .init(frequency: .monthly, weekdays: [3], weekOfMonth: 2))),
        ("毎月1日 振込",
         ParsedInput(title: "振込", recurrence: .init(frequency: .monthly, daysOfMonth: [1]))),
        ("3日ごと 水やり",
         ParsedInput(title: "水やり", recurrence: .init(frequency: .daily, interval: 3))),
        // 日付
        ("今日 レポート", ParsedInput(title: "レポート", date: ymd(2026, 11, 10))),
        ("明後日 午後3時 面談", ParsedInput(title: "面談", date: ymd(2026, 11, 12), time: hm(15))),
        ("来週水曜 歯医者", ParsedInput(title: "歯医者", date: ymd(2026, 11, 18))),
        ("火曜 提出", ParsedInput(title: "提出", date: ymd(2026, 11, 10))),
        ("11/20 締切", ParsedInput(title: "締切", date: ymd(2026, 11, 20))),
        ("11/5 締切", ParsedInput(title: "締切", date: ymd(2027, 11, 5))),
        ("11月20日 発表", ParsedInput(title: "発表", date: ymd(2026, 11, 20))),
        ("20日 支払い", ParsedInput(title: "支払い", date: ymd(2026, 11, 20))),
        ("5日 支払い", ParsedInput(title: "支払い", date: ymd(2026, 12, 5))),
        ("3日後 確認", ParsedInput(title: "確認", date: ymd(2026, 11, 13))),
        // 時刻
        ("夜 読書", ParsedInput(title: "読書", time: hm(20))),
        ("昼 薬", ParsedInput(title: "薬", time: hm(12))),
        ("9時半 会議", ParsedInput(title: "会議", time: hm(9, 30))),
        ("21時 電話", ParsedInput(title: "電話", time: hm(21))),
        ("午後1時-3時 作業 @予定", ParsedInput(title: "作業", kind: .event, time: hm(13), endTime: hm(15))),
        ("１０時 全角", ParsedInput(title: "全角", time: hm(10))),
        // リスト・種別・タイトル
        ("買い物 #仕事 牛乳", ParsedInput(title: "買い物 牛乳", listName: "仕事")),
        ("21時 電話 @予定", ParsedInput(title: "電話", kind: .event, time: hm(21))),
        ("夜景を見に行く", ParsedInput(title: "夜景を見に行く")),
        ("  空白   整理  ", ParsedInput(title: "空白 整理")),
        // 助詞・接尾辞
        ("明日の15時 歯医者", ParsedInput(title: "歯医者", date: ymd(2026, 11, 11), time: hm(15))),
        ("来週の月曜 会議", ParsedInput(title: "会議", date: ymd(2026, 11, 16))),
        ("再来週月曜 会議", ParsedInput(title: "会議", date: ymd(2026, 11, 23))),
        ("3日後の朝 提出", ParsedInput(title: "提出", date: ymd(2026, 11, 13), time: hm(8))),
        ("15:00に電話", ParsedInput(title: "電話", time: hm(15))),
        ("午後 3時 歯医者", ParsedInput(title: "歯医者", time: hm(15))),
        // 期間の語を時刻・日付に取らない
        ("3時間 勉強", ParsedInput(title: "3時間 勉強")),
        ("3日間 出張", ParsedInput(title: "3日間 出張")),
        // 時間帯の区切り
        ("10時~11時 打合せ", ParsedInput(title: "打合せ", kind: .event, time: hm(10), endTime: hm(11))),
        ("10時－11時 打合せ", ParsedInput(title: "打合せ", kind: .event, time: hm(10), endTime: hm(11))),
        ("10-11時 会議", ParsedInput(title: "会議", kind: .event, time: hm(10), endTime: hm(11))),
        ("10時から11時 会議", ParsedInput(title: "会議", kind: .event, time: hm(10), endTime: hm(11))),
        ("10時〜11時半 会議", ParsedInput(title: "会議", kind: .event, time: hm(10), endTime: hm(11, 30))),
        // 繰り返しの語がタイトルを食わない
        ("毎週日報提出", ParsedInput(title: "毎週日報提出")),
        ("毎週水泳", ParsedInput(title: "毎週水泳")),
        ("毎週 振り返り", ParsedInput(title: "振り返り", recurrence: .init(frequency: .weekly))),
        // リスト名は日付より先に取る
        ("#月曜会議 資料", ParsedInput(title: "資料", listName: "月曜会議")),
        ("12/31 23:59 年越し", ParsedInput(title: "年越し", date: ymd(2026, 12, 31), time: hm(23, 59))),
    ])
    func parsesTable(input: String, expected: ParsedInput) {
        #expect(parse(input) == expected)
    }

    @Test func dayOfMonthRollsIntoNextYear() {
        let december = tokyo.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 10))!
        let parsed = JapaneseInputParser().parse("5日 支払い", reference: december, calendar: tokyo)
        #expect(parsed.date == ymd(2027, 1, 5))
    }

    @Test func leapDayPicksNextLeapYear() {
        let parsed = parse("2/29 誕生日")
        #expect(parsed.date == ymd(2028, 2, 29))
        #expect(parsed.title == "誕生日")
    }
}

@Suite struct RecurrenceSpecTests {
    private func first(_ spec: RecurrenceSpec) -> DateComponents? {
        spec.firstOccurrence(onOrAfter: reference, calendar: tokyo)
            .map { tokyo.dateComponents([.year, .month, .day], from: $0) }
    }

    @Test func dailyStartsToday() {
        #expect(first(.init(frequency: .daily, interval: 3)) == ymd(2026, 11, 10))
    }

    @Test func weeklyPicksNextMatchingWeekdayIncludingToday() {
        #expect(first(.init(frequency: .weekly, weekdays: [2])) == ymd(2026, 11, 16))
        #expect(first(.init(frequency: .weekly, weekdays: [3])) == ymd(2026, 11, 10))
        #expect(first(.init(frequency: .weekly, weekdays: [2, 4, 6])) == ymd(2026, 11, 11))
    }

    @Test func monthlyByDayRollsToNextMonthAndSkipsShortMonths() {
        #expect(first(.init(frequency: .monthly, daysOfMonth: [15])) == ymd(2026, 11, 15))
        #expect(first(.init(frequency: .monthly, daysOfMonth: [1])) == ymd(2026, 12, 1))
        #expect(first(.init(frequency: .monthly, daysOfMonth: [31])) == ymd(2026, 12, 31))
    }

    @Test func monthlyByNthAndLastWeekday() {
        // 2026-11 の火曜は 3, 10, 17, 24。参照日 11/10 が第 2 火曜
        #expect(first(.init(frequency: .monthly, weekdays: [3], weekOfMonth: 2)) == ymd(2026, 11, 10))
        #expect(first(.init(frequency: .monthly, weekdays: [3], weekOfMonth: 1)) == ymd(2026, 12, 1))
        #expect(first(.init(frequency: .monthly, weekdays: [6], weekOfMonth: -1)) == ymd(2026, 11, 27))
    }
}

@Suite struct ParsedInputDraftTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func draft(_ text: String) -> ItemDraft {
        parse(text).draft(reference: reference, calendar: tokyo)
    }

    @Test func noDateNoTimeIsUndated() {
        let d = draft("牛乳買う")
        #expect(d.start == nil)
        #expect(d.isAllDay == false)
    }

    @Test func timeOnlyIsToday() {
        let d = draft("夜 読書")
        #expect(d.start == date(2026, 11, 10, 20))
        #expect(d.isAllDay == false)
    }

    @Test func pastTimeWithoutDateRollsToTomorrow() {
        // 参照は 10:00。8:00 は過ぎているので明日
        #expect(draft("朝 ゴミ出し").start == date(2026, 11, 11, 8))
        // 日付を明示していれば過去でもそのまま
        #expect(draft("今日 朝 ゴミ出し").start == date(2026, 11, 10, 8))
    }

    @Test func recurrenceWithPastTimeTodaySkipsToNextOccurrence() {
        // 火曜 10:00 に「毎週火曜 9時」→ 来週の火曜
        #expect(draft("毎週火曜 9時 定例").start == date(2026, 11, 17, 9))
        #expect(draft("毎日 朝 ストレッチ").start == date(2026, 11, 11, 8))
        // 時刻が未来なら今日
        #expect(draft("毎週火曜 15時 定例").start == date(2026, 11, 10, 15))
    }

    @Test func dateOnlyIsAllDay() {
        let d = draft("明日 歯医者")
        #expect(d.start == date(2026, 11, 11))
        #expect(d.isAllDay)
        #expect(d.end == nil)
    }

    @Test func recurrenceWithoutDateStartsAtFirstOccurrence() {
        #expect(draft("毎週月曜 ゴミ出し").start == date(2026, 11, 16))
        #expect(draft("毎週月曜 9時 ゴミ出し").start == date(2026, 11, 16, 9))
    }

    @Test func eventEndDefaultsToOneHour() {
        let d = draft("金曜 10時-11時 面談 @予定")
        #expect(d.kind == .event)
        #expect(d.start == date(2026, 11, 13, 10))
        #expect(d.end == date(2026, 11, 13, 11))

        let oneHour = draft("21時 電話 @予定")
        #expect(oneHour.end == date(2026, 11, 10, 22))
    }

    @Test func eventEndBeforeStartWrapsToNextDay() {
        let d = draft("23時-1時 夜勤 @予定")
        #expect(d.start == date(2026, 11, 10, 23))
        #expect(d.end == date(2026, 11, 11, 1))
    }

    @Test func allDayEventHasEndOnSameDay() {
        let d = draft("明日 休暇 @予定")
        #expect(d.isAllDay)
        #expect(d.end == date(2026, 11, 11))
    }
}
