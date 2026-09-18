import SwiftUI
import UIKit

/// UIKit owns retained destinations, tab transitions, and the floating bar.
final class AppTabBarController: UITabBarController, UITabBarControllerDelegate {
    private enum Destination: Int { case dictionary, feed, add, player, settings }
    private let dependencies: AppDependencies
    private let session: AppSession
    private let settingsController: SettingsTabController
    private var navigationBar: (any MainNavigationBar)?
    private var isTransitioning = false
    private var requestedIndex = Destination.dictionary.rawValue

    init(dependencies: AppDependencies, session: AppSession) {
        self.dependencies = dependencies
        self.session = session
        settingsController = SettingsTabController(database: dependencies.database, session: session)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(AppColors.background)
        delegate = self
        setTabBarHidden(true, animated: false)
        let shortcuts = SettingsRoute.shortcuts.map { shortcut in
            MainNavigationAction(id: shortcut.symbol, title: String(localized: shortcut.title), symbol: shortcut.symbol) { [weak self] in
                self?.openSettings(shortcut.route)
            }
        }
        let navigationBar = MainNavigation(items: [
            MainNavigationItem(title: "Dictionary", symbol: "books.vertical"),
            MainNavigationItem(title: "Feed", symbol: "rectangle.stack"),
            MainNavigationItem(title: "Add", symbol: "plus.circle"),
            MainNavigationItem(title: "Player", symbol: "play.circle"),
            MainNavigationItem(title: String(localized: "title", table: "Settings"), symbol: "gearshape", contextActions: shortcuts),
        ])
        self.navigationBar = navigationBar
        navigationBar.selectionChanged = { [weak self] index in self?.select(index) }
        viewControllers = [
            UIHostingController(rootView: NavigationStack { PlaceholderView(title: "Dictionary", symbol: "books.vertical.fill") }),
            FeedViewController(
                database: dependencies.database,
                settings: session.settings,
                pronunciation: dependencies.pronunciation,
                mediaCache: dependencies.mediaCache
            ) { [weak self] in
                self?.select(Destination.dictionary.rawValue)
            },
            UIHostingController(rootView: NavigationStack {
                AddCardView(settings: session.settings,
                            generation: CardTitleGeneration(supabase: dependencies.supabase),
                            pronunciation: dependencies.pronunciation) { selection in
                    // TODO: Insert the card once the breakdown workflow exists.
                    print("[add-card] chosen title", selection.variant.title)
                }
            }.environment(session.settings)),
            UIHostingController(rootView: NavigationStack { PlaceholderView(title: "Player", symbol: "play.circle.fill") }),
            settingsController,
        ]
        for child in viewControllers ?? [] {
            child.additionalSafeAreaInsets.bottom = navigationBar.metrics.height + navigationBar.metrics.contentGap
        }
        let bar = navigationBar.view
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        let metrics = navigationBar.metrics
        let width = bar.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -2 * metrics.sideInset)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: metrics.height),
            width,
        ])
        if let maximumWidth = metrics.maximumWidth {
            bar.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true
        }
        navigationBar.select(selectedIndex, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let navigationBar { view.bringSubviewToFront(navigationBar.view) }
    }

    func openSettings(_ route: SettingsRoute) {
        loadViewIfNeeded()
        select(Destination.settings.rawValue)
        settingsController.open(route)
    }

    private func select(_ index: Int) {
        guard let viewControllers, viewControllers.indices.contains(index) else { return }
        requestedIndex = index
        navigationBar?.select(index, animated: true)
        applyRequestedSelection()
    }

    private func applyRequestedSelection() {
        guard !isTransitioning, selectedIndex != requestedIndex else { return }
        selectedViewController?.view.endEditing(true)
        selectedIndex = requestedIndex
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        isTransitioning = true
        return ScreenTransitionAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.14) { [weak self] in
            // Let UIKit finish its containment and appearance callbacks before
            // applying the latest tap. Never expose a half-finished fade.
            DispatchQueue.main.async { [weak self] in
                self?.isTransitioning = false
                self?.applyRequestedSelection()
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: LocalizedStringResource
    let symbol: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(AppColors.textSecondary)
            Text(title).font(.system(size: 32, weight: .semibold)).foregroundStyle(AppColors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .navigationTitle(Text(title))
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}

private final class ScreenTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let duration: TimeInterval
    let completion: () -> Void

    init(duration: TimeInterval, completion: @escaping () -> Void) {
        self.duration = duration
        self.completion = completion
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        duration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let destination = transitionContext.viewController(forKey: .to),
              let outgoing = transitionContext.view(forKey: .from),
              let incoming = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            completion()
            return
        }

        let container = transitionContext.containerView
        UIView.performWithoutAnimation {
            container.addSubview(outgoing)
            incoming.frame = transitionContext.finalFrame(for: destination)
            // Settle the hosting view's safe area and navigation chrome while
            // it is covered by the outgoing screen, before taking snapshots.
            container.insertSubview(incoming, belowSubview: outgoing)
            incoming.setNeedsLayout()
            container.setNeedsLayout()
            container.layoutIfNeeded()
            incoming.isHidden = true
        }

        UIView.transition(
            from: outgoing,
            to: incoming,
            duration: duration,
            options: [.transitionCrossDissolve, .curveEaseInOut, .showHideTransitionViews]
        ) { _ in
            let completed = !transitionContext.transitionWasCancelled
            if completed {
                outgoing.removeFromSuperview()
            } else {
                incoming.removeFromSuperview()
            }
            outgoing.isHidden = false
            incoming.isHidden = false
            transitionContext.completeTransition(completed)
            self.completion()
        }
    }
}
