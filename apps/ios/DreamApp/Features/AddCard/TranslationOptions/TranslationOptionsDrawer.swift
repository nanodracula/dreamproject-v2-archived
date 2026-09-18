import SwiftUI
import UIKit

/// Bridges feature state to a UIKit custom presentation without a SwiftUI modal.
struct TranslationOptionsDrawer: UIViewControllerRepresentable {
    @Binding var session: TitlePickerSession?
    let pronunciation: Pronunciation
    let onConfirm: (TitlePickerSession, CardTitleVariant) -> Void

    func makeUIViewController(context: Context) -> Presenter {
        Presenter(configuration: self)
    }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.configuration = self
        controller.updatePresentation()
    }

    static func dismantleUIViewController(_ controller: Presenter, coordinator: ()) {
        controller.drawer?.dismiss(animated: false)
    }

    final class Presenter: UIViewController {
        var configuration: TranslationOptionsDrawer
        fileprivate var drawer: TranslationOptionsController?

        init(configuration: TranslationOptionsDrawer) {
            self.configuration = configuration
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updatePresentation()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // A custom presentation leaves its presenter visible. This callback
            // therefore means the feature itself has left the screen.
            drawer?.dismiss(animated: false)
        }

        func updatePresentation() {
            guard let session = configuration.session else {
                if let drawer, !drawer.isBeingDismissed { drawer.dismiss(animated: true) }
                return
            }
            guard drawer == nil, let window = viewIfLoaded?.window else { return }

            let drawer = TranslationOptionsController(
                session: session,
                pronunciation: configuration.pronunciation,
                onConfirm: { [weak self] variant in
                    self?.configuration.onConfirm(session, variant)
                },
                onDismiss: { [weak self] in
                    guard let self else { return }
                    self.drawer = nil
                    if configuration.session?.id == session.id {
                        configuration.session = nil
                    }
                }
            )
            self.drawer = drawer
            drawer.prepareForPresentation(in: window)
            present(drawer, animated: true)
        }
    }
}

/// Hosts the sheet inside the shared drawer presentation. SwiftUI reports its
/// natural height and header zone; the drawer owns frame, backdrop, motion,
/// and drag-to-dismiss.
private final class TranslationOptionsController: UIHostingController<TranslationOptionsSheet> {
    private var drawer: DrawerPresentation!

    init(session: TitlePickerSession, pronunciation: Pronunciation,
         onConfirm: @escaping (CardTitleVariant) -> Void, onDismiss: @escaping () -> Void) {
        super.init(rootView: TranslationOptionsSheet(
            session: session, pronunciation: pronunciation,
            onConfirm: onConfirm, onDismiss: {}, onSizeChange: { _, _ in }
        ))
        drawer = DrawerPresentation(
            controller: self,
            appearance: DrawerAppearance(backgroundColor: UIColor(AddCardColors.background)),
            onDismiss: onDismiss
        )
        rootView = TranslationOptionsSheet(
            session: session, pronunciation: pronunciation,
            onConfirm: onConfirm,
            onDismiss: { [weak self] in self?.dismiss(animated: true) },
            onSizeChange: { [weak self] height, headerHeight in
                guard let self else { return }
                drawer.headerHeight = headerHeight
                drawer.setContentHeight(height)
            }
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
            // Resolve SwiftUI's initial measurements before UIKit starts the transition.
            rootView.measuresContent = true
            defer { rootView.measuresContent = false }
            return sizeThatFits(in: CGSize(width: window.bounds.width, height: .greatestFiniteMagnitude))
        }
    }
}
