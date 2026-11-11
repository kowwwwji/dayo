import Foundation

/// 予定のメモを、自分で書いた本文と、Google カレンダーが末尾に足すビデオ会議の案内とに分ける。
/// 案内は区切り線 2 本で囲まれたブロックで、参加用の URL と「このセクションは編集しないでください」の文言が入っている。
/// 画面では本文だけを編集させ、保存時は案内を元のまま付け直す（Google が管理する部分なので書き換えない）。
public struct ConferenceNotes: Equatable {
    /// 案内を除いたメモ。
    public let body: String
    /// 案内の中の最初の URL（参加用のリンク）。案内が無ければ nil。
    public let url: URL?

    private let original: String
    private let block: String?
    /// 案内の後ろに書かれていた本文。付け直すときに案内の後ろへ戻す。
    private let tail: String

    public init(_ notes: String) {
        original = notes
        let lines = notes.components(separatedBy: "\n")
        let separators = lines.indices.filter { Self.isSeparator(lines[$0]) }
        guard let first = separators.first, let last = separators.last, first < last else {
            body = notes
            url = nil
            block = nil
            tail = ""
            return
        }
        let blockText = lines[first...last].joined(separator: "\n")
        let head = Self.trimmed(lines[..<first].joined(separator: "\n"))
        tail = Self.trimmed(lines[(last + 1)...].joined(separator: "\n"))
        block = blockText
        body = [head, tail].filter { !$0.isEmpty }.joined(separator: "\n")
        url = Self.firstURL(in: blockText)
    }

    /// 編集後の本文に案内を付け直した、保存用のメモ。本文を変えていなければ元のメモをそのまま返す。
    public func combined(withBody edited: String) -> String {
        guard let block else { return edited }
        if edited == body { return original }
        var text = Self.trimmed(edited)
        // 案内の後ろにあった本文は、編集後も同じなら後ろへ戻す。変わっていれば全部を案内の前に置く
        var after = ""
        if !tail.isEmpty, text.hasSuffix(tail) {
            text = Self.trimmed(String(text.dropLast(tail.count)))
            after = "\n" + tail
        }
        return (text.isEmpty ? "" : text + "\n\n") + block + after
    }

    /// 区切り線は `-::~:~::~:~:~: … :~::~:~::-` の形。長さは決まっていないので、両端と使われる文字で見分ける。
    private static func isSeparator(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count >= 20 && text.hasPrefix("-::~:~::~") && text.hasSuffix("::~:~::-")
            && text.allSatisfy { "-:~".contains($0) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstURL(in text: String) -> URL? {
        guard let range = text.range(of: #"https?://[^\s<>"]+"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }
}
