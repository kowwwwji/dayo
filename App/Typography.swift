import SwiftUI

/// アプリ共通の小さめの文字。標準の caption（Mac で 10pt）では小さいので一回り大きくする。
/// iPhone は Dynamic Type に乗るようテキストスタイルで、Mac は固定サイズで指定する。
extension Font {
    /// グリッド内と終日チップの予定・リマインダーのタイトル。小さめの本文より 1pt 大きい。
    static var dayoTitle: Font {
        #if os(macOS)
        .system(size: 13)
        #else
        .callout
        #endif
    }

    /// チップ内の文字や補足見出しなど、小さめの本文。
    static var dayoSmall: Font {
        #if os(macOS)
        .system(size: 12)
        #else
        .subheadline
        #endif
    }

    /// 時刻・補足など、さらに控えめな文字。
    static var dayoDetail: Font {
        #if os(macOS)
        .system(size: 11)
        #else
        .footnote
        #endif
    }
}
