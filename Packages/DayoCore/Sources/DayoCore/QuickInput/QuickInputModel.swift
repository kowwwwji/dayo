import Foundation
import Observation

/// クイック入力欄の状態。入力文字列の解釈プレビューと登録を持つ。
@MainActor
@Observable
public final class QuickInputModel {
    public var text = "" {
        didSet { if text != oldValue { errorMessage = nil } }
    }
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    /// 登録に成功したあとに呼ぶ。タイムライン側の即時再読み込みに使う。
    public var onCreated: (@MainActor () async -> Void)?

    private let source: CalendarSource
    private let parser: InputParser
    private let calendar: Calendar
    private let now: () -> Date

    /// 既定はグレゴリオ暦。システムが和暦などでも「11/20」を西暦として解釈するため。
    /// タイムゾーンと週の始まりはユーザー設定に従う。
    nonisolated public static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        return calendar
    }

    public init(
        source: CalendarSource,
        parser: InputParser = JapaneseInputParser(),
        calendar: Calendar = QuickInputModel.defaultCalendar,
        now: @escaping () -> Date = { .now }
    ) {
        self.source = source
        self.parser = parser
        self.calendar = calendar
        self.now = now
    }

    /// 現在の入力の解釈。空なら nil。
    public var parsed: ParsedInput? {
        parsed(at: now())
    }

    private func parsed(at reference: Date) -> ParsedInput? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return parser.parse(trimmed, reference: reference, calendar: calendar)
    }

    public func submit() async {
        // 解釈と期日の確定で同じ基準時刻を使う（日付をまたいだ瞬間にずれないように）
        let reference = now()
        guard let parsed = parsed(at: reference), !isSubmitting else { return }
        guard !parsed.title.isEmpty else {
            errorMessage = "タイトルを入力してください"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await source.create(parsed.draft(reference: reference, calendar: calendar))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        text = ""
        errorMessage = nil
        await onCreated?()
    }
}
