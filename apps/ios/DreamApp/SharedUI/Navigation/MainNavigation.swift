import UIKit

/// Change this alias to MainNavigationTelegram to switch the floating bar.
typealias MainNavigation = MainNavigationOriginal

struct MainNavigationItem {
    let title: String
    let symbol: String
    var selectedSymbol: String { symbol + ".fill" }
    var contextActions: [MainNavigationAction] = []
}

struct MainNavigationAction {
    let id: String
    let title: String
    let symbol: String
    let action: () -> Void
}

protocol MainNavigationBar: AnyObject {
    var view: UIView { get }
    var metrics: MainNavigationMetrics { get }
    var selectionChanged: ((Int) -> Void)? { get set }
    func select(_ index: Int, animated: Bool)
}

extension MainNavigationBar where Self: UIView {
    var view: UIView { self }
}

struct MainNavigationMetrics {
    let height: CGFloat
    let sideInset: CGFloat
    var maximumWidth: CGFloat?
    var contentGap: CGFloat { 4 }
}
