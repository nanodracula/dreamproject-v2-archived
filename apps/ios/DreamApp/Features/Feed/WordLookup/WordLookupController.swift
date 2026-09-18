import SwiftUI
import UIKit

/// Hosts the lookup sheet in the shared drawer, anchored so its top edge
/// sits just under the chip row that opened it, and expandable by drag to
/// three quarters of the screen. The card stays visible and undimmed behind
/// it; a tap on the card dismisses.
final class WordLookupController: UIHostingController<WordLookupSheet> {
    private var drawer: DrawerPresentation!

    init(chunk: FeedChunk, context: FeedContext, pronunciation: Pronunciation,
         anchorTop: CGFloat, onDismiss: @escaping () -> Void) {
        super.init(rootView: WordLookupSheet(
            chunk: chunk, context: context, pronunciation: pronunciation,
            onDismiss: {}, onHeaderHeightChange: { _ in }
        ))
        drawer = DrawerPresentation(
            controller: self,
            appearance: DrawerAppearance(
                backgroundColor: .clear,
                dimsPresenter: false,
                height: .anchored(top: anchorTop, expandedFraction: 0.75)
            ),
            onDismiss: onDismiss
        )
        rootView = WordLookupSheet(
            chunk: chunk, context: context, pronunciation: pronunciation,
            onDismiss: { [weak self] in self?.dismiss(animated: true) },
            onHeaderHeightChange: { [weak self] height in self?.drawer.headerHeight = height }
        )
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        drawer.attach(to: view)
    }

    func prepareForPresentation(in window: UIWindow) {
        drawer.prepareForPresentation(in: window) {
            sizeThatFits(in: CGSize(width: window.bounds.width, height: window.bounds.height))
        }
    }
}
