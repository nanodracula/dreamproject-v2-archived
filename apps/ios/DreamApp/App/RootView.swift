import SwiftUI

/// The top-level destinations. Their order, labels, and screens are declared
/// together in `RootView.screens`.
nonisolated private enum AppDestination: Hashable {
    case dictionary
    case feed
    case add
    case player
    case settings
}

/// Hosts a navigation stack per tab, with a custom glass bar in the bottom safe area.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppSettingsModel.self) private var settings
    @State private var selectedDestination: AppDestination = .dictionary
    @State private var settingsPath: [SettingsRoute] = []

    private var navigationMetrics: MainNavigationMetrics {
        MainNavigation<Screen<AppDestination>>.metrics
    }

    var body: some View {
        let screens = screens
        ScreenTransitionView(screens: screens, selection: selectedDestination)
            // UIKit owns the screen's safe areas. The bar overlays it, while
            // each hosted screen reserves scrolling space without clipping its
            // background.
            .ignoresSafeArea(.container)
            .overlay(alignment: .bottom) {
                MainNavigation(items: screens, selection: $selectedDestination)
                    .padding(.horizontal, navigationMetrics.sideInset)
            }
            // The bar floats in place over the keyboard; each hosted screen
            // avoids the keyboard on its own.
            .ignoresSafeArea(.keyboard)
            .background(AppColors.background)
    }

    /// Every root screen in bar order, each with its label and its own
    /// navigation stack. Adding a screen is adding one entry here.
    private var screens: [Screen<AppDestination>] {
        [
            Screen(.dictionary, "Dictionary", symbol: "books.vertical") {
                hosted(NavigationStack { PlaceholderView(title: "Dictionary", symbol: "books.vertical.fill") })
            },
            Screen(.feed, "Feed", symbol: "rectangle.stack") {
                hosted(NavigationStack { PlaceholderView(title: "Feed", symbol: "rectangle.stack.fill") })
            },
            Screen(.add, "Add", symbol: "plus.circle") {
                hosted(NavigationStack { AddCardView(dependencies: dependencies, onSelection: createCard) })
            },
            Screen(.player, "Player", symbol: "play.circle") {
                hosted(NavigationStack { PlaceholderView(title: "Player", symbol: "play.circle.fill") })
            },
            Screen(
                .settings,
                LocalizedStringResource("title", table: "Settings"),
                symbol: "gearshape",
                actions: settingsActions
            ) {
                hosted(NavigationStack(path: $settingsPath) { SettingsView() })
            },
        ]
    }

    /// A screen's stack with room kept for the floating bar, and the app's
    /// shared objects re-injected, since UIKit hosting breaks the
    /// environment chain.
    private func hosted(_ stack: some View) -> some View {
        stack
            .safeAreaInset(edge: .bottom, spacing: navigationMetrics.contentGap) {
                Color.clear.frame(height: navigationMetrics.height)
            }
            .environment(dependencies)
            .environment(settings)
    }

    private var settingsActions: [MainNavigationAction] {
        SettingsRoute.shortcuts.map { shortcut in
            MainNavigationAction(id: shortcut.symbol, title: shortcut.title, symbol: shortcut.symbol) {
                selectedDestination = .settings
                settingsPath = [shortcut.route]
            }
        }
    }

    // TODO: Create the card from the chosen title once the breakdown
    // workflow and a local insert path exist.
    private func createCard(from selection: AddCardSelection) {
        print("[add-card] chosen title", selection.variant.title)
    }
}

/// Stands in for a feature screen until it is implemented.
private struct PlaceholderView: View {
    let title: LocalizedStringResource
    let symbol: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary)
            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppColors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .navigationTitle(Text(title))
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

#Preview {
    RootView()
        .previewDependencies()
}
