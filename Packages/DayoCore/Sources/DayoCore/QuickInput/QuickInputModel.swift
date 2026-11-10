import Foundation
import Observation

/// クイック入力欄の状態。入力文字列の解釈プレビュー、`#` `@` の保存先補完、登録を持つ。
@MainActor
@Observable
public final class QuickInputModel {
    public var text = "" {
        didSet {
            if text != oldValue {
                errorMessage = nil
                selectedSuggestionID = nil
            }
        }
    }
    /// Tab で選んでいる候補。入力が変わると外れる。
    public private(set) var selectedSuggestionID: Destination.ID?
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    /// 補完候補の元になる保存先一覧。`loadDestinations()` で取り直す。
    public private(set) var destinations: [Destination] = []
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

    // MARK: - 保存先の補完

    /// 失敗しても候補が出ないだけなので、エラーは表示しない。
    public func loadDestinations() async {
        if let loaded = try? await source.destinations() {
            destinations = loaded
        }
    }

    /// 入力末尾が `#` か `@` で始まる語なら、その語に前方一致する保存先。完全に打ち終えた名前は出さない。
    public var suggestions: [Destination] {
        guard let token = Self.trailingMarkerToken(in: text) else { return [] }
        let kind: ItemKind = token.marker == "#" ? .reminder : .event
        return destinations
            .filter { $0.kind == kind }
            .filter { Self.matches($0.name, prefix: token.name) }
            .filter { $0.name.compare(token.name, options: Self.compareOptions) != .orderedSame }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 候補を選んだ。入力末尾の `#…` `@…` をその名前に置き換え、続けて打てるよう空白を足す。
    public func apply(_ destination: Destination) {
        guard let token = Self.trailingMarkerToken(in: text) else { return }
        text = text[..<token.range.lowerBound] + token.marker + destination.name + " "
    }

    /// Tab: 候補を順に選ぶ。末尾まで来たら先頭に戻る。
    public func selectNextSuggestion() {
        moveSelection(by: 1)
    }

    /// Shift+Tab: 前の候補へ。先頭から戻ると末尾。
    public func selectPreviousSuggestion() {
        moveSelection(by: -1)
    }

    private func moveSelection(by offset: Int) {
        let current = suggestions
        guard !current.isEmpty else { return }
        if let id = selectedSuggestionID, let index = current.firstIndex(where: { $0.id == id }) {
            selectedSuggestionID = current[(index + offset + current.count) % current.count].id
        } else {
            selectedSuggestionID = (offset > 0 ? current.first : current.last)?.id
        }
    }

    /// Return: 選んでいる候補があれば補完して true。無ければ false（呼び出し側は登録に進む）。
    public func applySelectedSuggestion() -> Bool {
        guard let id = selectedSuggestionID, let destination = suggestions.first(where: { $0.id == id }) else {
            return false
        }
        apply(destination)
        return true
    }

    /// 入力末尾に `#` か `@` の語があるか。候補一覧を読み直すきっかけに使う。
    public var hasTrailingMarker: Bool {
        Self.trailingMarkerToken(in: text) != nil
    }

    private struct MarkerToken {
        /// 半角に寄せた印（`#` か `@`）。
        let marker: String
        let name: String
        let range: Range<String.Index>
    }

    /// 日本語入力では `＃` `＠` が全角で入るので、どちらも印として扱う。
    private static let markers: [Character: String] = ["#": "#", "＃": "#", "@": "@", "＠": "@"]

    private static let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    private static func matches(_ name: String, prefix: String) -> Bool {
        prefix.isEmpty || name.range(of: prefix, options: compareOptions.union(.anchored)) != nil
    }

    private static func trailingMarkerToken(in text: String) -> MarkerToken? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        let start = text.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        let token = text[start...]
        guard let first = token.first, let marker = markers[first] else { return nil }
        return MarkerToken(marker: marker, name: String(token.dropFirst()), range: start..<text.endIndex)
    }
}
