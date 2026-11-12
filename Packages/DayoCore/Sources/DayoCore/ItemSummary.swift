import Foundation

/// 項目の中身を、見るだけの形にまとめたもの。情報カードに出す。値の無い行は nil。
/// 場所・URL・ビデオ会議のリンクの作り方はここに 1 つだけ置き、編集ポップオーバー（`ItemEditorModel`）も同じものを使う。
public struct ItemSummary: Equatable {
    /// 「11/11 (水) 17:30–18:30」のような日時。期日なしのリマインダーは nil。
    public let dateText: String?
    /// 「毎週水曜」のような繰り返しの説明。このアプリで表せない規則は「繰り返しあり」。
    public let recurrenceText: String?
    /// event のみ。前後の空白を除いた場所。
    public let location: String?
    /// 場所を Google マップで検索する URL。
    public let locationMapURL: URL?
    /// 項目に付いている URL のうち、ブラウザで開けるもの。
    public let linkURL: URL?
    /// メモに入っていたビデオ会議の参加用リンク。
    public let conferenceURL: URL?
    /// メモ。Google カレンダーが足すビデオ会議の案内は除いてある。
    public let notes: String?

    public init(_ item: TimelineItem, calendar: Calendar = QuickInputModel.defaultCalendar, now: Date = .now) {
        dateText = Self.dateText(for: item, calendar: calendar, now: now)
        recurrenceText = Self.recurrenceText(for: item, calendar: calendar)
        let place = Self.trimmedLocation(item.location)
        location = place.isEmpty ? nil : place
        locationMapURL = Self.mapURL(forLocation: place)
        linkURL = Self.webURL(item.url)
        let conference = ConferenceNotes(item.notes ?? "")
        conferenceURL = conference.url
        let body = conference.body.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = body.isEmpty ? nil : body
    }

    /// 押して開けるリンクを、画面の並び（場所 → URL → ビデオ会議）で。キーでリンクを選ぶ順に使う。
    public var links: [URL] {
        [locationMapURL, linkURL, conferenceURL].compactMap { $0 }
    }

    // MARK: - リンク

    static func trimmedLocation(_ location: String?) -> String {
        location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 場所を Google マップで検索する URL。場所が空なら nil。
    static func mapURL(forLocation location: String) -> URL? {
        guard !location.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: location)]
        // URLComponents は値の中の「+」をそのまま残す。受け側では空白と読まれるので、自分でエスケープする
        let encoded = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encoded
        return components?.url
    }

    /// ブラウザで開ける URL（http / https）ならそのまま返す。それ以外は、押して開くリンクにしない。
    static func webURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        return url
    }

    // MARK: - 繰り返し

    private static func recurrenceText(for item: TimelineItem, calendar: Calendar) -> String? {
        guard item.hasRecurrence else { return nil }
        guard let spec = item.recurrence else { return "繰り返しあり" }
        guard let start = item.start else { return spec.localizedDescription }
        return spec.normalized(from: start, calendar: calendar).localizedDescription
    }

    // MARK: - 日時

    private static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]

    private static func dateText(for item: TimelineItem, calendar: Calendar, now: Date) -> String? {
        guard let start = item.start else { return nil }
        let year = calendar.component(.year, from: now)
        func day(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let prefix = parts.year == year ? "" : "\(parts.year ?? 0)/"
            return "\(prefix)\(parts.month ?? 0)/\(parts.day ?? 0) (\(weekdayNames[(parts.weekday ?? 1) - 1]))"
        }
        func time(_ date: Date) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }

        guard item.kind == .event, let end = item.end, end > start else {
            return item.isAllDay ? day(start) : "\(day(start)) \(time(start))"
        }
        // 翌日 0:00 に終わる予定は、その日まで延びていない（前の日の 24:00 に終わったものとして書く）
        let endsAtMidnight = end == calendar.startOfDay(for: end)
        let lastDay = endsAtMidnight ? end.addingTimeInterval(-1) : end
        let isSameDay = calendar.isDate(start, inSameDayAs: lastDay)
        if item.isAllDay {
            return isSameDay ? day(start) : "\(day(start)) – \(day(lastDay))"
        }
        let endTime = endsAtMidnight ? "24:00" : time(end)
        return isSameDay
            ? "\(day(start)) \(time(start))–\(endTime)"
            : "\(day(start)) \(time(start)) – \(day(lastDay)) \(endTime)"
    }
}

extension RecurrenceSpec {
    /// 曜日や日を省いた「毎週」「毎月」（純正アプリがよく作る形）を開始日時で補い、曜日の順序を揃える。
    /// 規則どうしの比較と、説明の文字に使う。
    func normalized(from start: Date, calendar: Calendar) -> RecurrenceSpec {
        var result = self
        switch frequency {
        case .weekly where weekdays.isEmpty:
            result.weekdays = [calendar.component(.weekday, from: start)]
        case .monthly where daysOfMonth.isEmpty && weekOfMonth == nil:
            result.daysOfMonth = [calendar.component(.day, from: start)]
        default:
            break
        }
        result.weekdays.sort()
        return result
    }
}
