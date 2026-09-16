import SwiftUI

/// Shared entry point for the app's navigation bar and its selected layout.
struct MainNavigation<Item: MainNavigationItem>: View {
    let items: [Item]
    @Binding var selection: Item.ID

    /// Uses the active bar's layout so spacing follows the choice in `body`.
    static var metrics: MainNavigationMetrics { Body.metrics }

    /// Keep exactly one implementation uncommented, then rebuild to switch bars.
    var body: some MainNavigationBar {
        // Telegram: glass lens animation and long-press context menus.
        // MainNavigationTelegram(items: items, selection: $selection)

        // Original: our SwiftUI pill animation, with no long-press menu.
        MainNavigationOriginal(items: items, selection: $selection)
    }
}

/// What the bar shows for one destination. Selection is by `id`, so the
/// item itself can carry view content.
nonisolated protocol MainNavigationItem: Identifiable where ID: Hashable {
    var title: LocalizedStringResource { get }
    var symbol: String { get }
    var selectedSymbol: String { get }
    /// Long-press shortcuts, when the bar supports them.
    var contextActions: [MainNavigationAction] { get }
}

nonisolated extension MainNavigationItem {
    var contextActions: [MainNavigationAction] { [] }
}

struct MainNavigationAction: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let symbol: String
    let action: () -> Void
}

protocol MainNavigationBar: View {
    static var metrics: MainNavigationMetrics { get }
}

struct MainNavigationMetrics {
    let height: CGFloat
    let sideInset: CGFloat
    var contentGap: CGFloat { 4 }
}

#Preview {
    nonisolated struct PreviewItem: MainNavigationItem {
        let title: LocalizedStringResource
        let symbol: String
        let selectedSymbol: String

        var id: String { symbol }
    }

    struct Host: View {
        let items = [
            PreviewItem(title: "Dictionary", symbol: "books.vertical", selectedSymbol: "books.vertical.fill"),
            PreviewItem(title: "Feed", symbol: "rectangle.stack", selectedSymbol: "rectangle.stack.fill"),
            PreviewItem(title: "Settings", symbol: "gearshape", selectedSymbol: "gearshape.fill"),
        ]
        @State private var selection = "books.vertical"

        var body: some View {
            MainNavigation(items: items, selection: $selection)
                .padding(.horizontal, MainNavigation<PreviewItem>.metrics.sideInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(AppColors.background)
        }
    }

    return Host().preferredColorScheme(.dark)
}
