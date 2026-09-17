import UIKit

/// UIKit adapter for the existing Telegram port and its long-press shortcuts.
final class MainNavigationTelegram: UIView, MainNavigationBar {
    let metrics = MainNavigationMetrics(height: 64, sideInset: 12, maximumWidth: 500)
    var selectionChanged: ((Int) -> Void)?
    private let bar = TelegramTabBarView(frame: .zero)
    private let items: [TelegramTabBarItem]

    init(items: [MainNavigationItem]) {
        let icon = UIImage.SymbolConfiguration(pointSize: 27, weight: .regular)
        let menuIcon = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        self.items = items.enumerated().map { index, item in
            TelegramTabBarItem(
                id: AnyHashable(index), title: item.title,
                image: UIImage(systemName: item.symbol, withConfiguration: icon),
                selectedImage: UIImage(systemName: item.selectedSymbol, withConfiguration: icon),
                contextActions: item.contextActions.map { action in
                    TelegramContextMenuAction(id: action.id, title: action.title,
                                              icon: UIImage(systemName: action.symbol, withConfiguration: menuIcon),
                                              action: action.action)
                }
            )
        }
        super.init(frame: .zero)
        addSubview(bar)
        bar.selectionChanged = { [weak self] id in
            guard let index = id.base as? Int else { return }
            self?.selectionChanged?(index)
        }
        select(0, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        bar.frame = bounds
    }

    func select(_ index: Int, animated: Bool) {
        bar.update(items: items, selectedId: AnyHashable(index), reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)
    }
}
