#if os(macOS)
import AppKit
import SwiftUI

/// アカウントの追加。アプリからはアカウントを足せないので、システム設定の「インターネットアカウント」を開く。
/// 足したアカウントは変更の通知で読み直されて、そのまま画面に出る。
enum AccountSetup {
    private static let internetAccounts = URL(
        string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
    )!

    static func open() {
        NSWorkspace.shared.open(internetAccounts)
    }
}

/// インターネットアカウントのカレンダーが 1 つも無いときに、タイムラインの上に出す案内。
struct AccountPromptBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .foregroundStyle(.tint)
            Text("Google や iCloud の予定とリマインダーを出すには、アカウントを追加してください。")
                .font(.dayoSmall)
            Spacer(minLength: 0)
            Button("アカウントを追加…") { AccountSetup.open() }
                .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.tint.opacity(0.1))
    }
}
#endif
