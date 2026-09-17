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

private final class TranslationOptionsController: UIHostingController<TranslationOptionsSheet>,
    UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
    private let didDismiss: () -> Void
    private var contentHeight: CGFloat = 0
    private var headerHeight: CGFloat = 81
    private var returnAnimator: UIViewPropertyAnimator?
    private weak var draggedScrollView: UIScrollView?
    private var dismissalVelocity: CGFloat = 0
    private var hasTakenOverScroll = false
    private var dragOrigin: CGFloat = 0
    private var dragStartOffset: CGFloat = 0
    private var dragOffset: CGFloat = 0

    private var drawerPresentation: DrawerPresentationController? {
        presentationController as? DrawerPresentationController
    }

    init(session: TitlePickerSession, pronunciation: Pronunciation,
         onConfirm: @escaping (CardTitleVariant) -> Void, onDismiss: @escaping () -> Void) {
        didDismiss = onDismiss
        super.init(rootView: TranslationOptionsSheet(
            session: session, pronunciation: pronunciation,
            onConfirm: onConfirm, onDismiss: {}, onSizeChange: { _, _ in }
        ))
        rootView = TranslationOptionsSheet(
            session: session, pronunciation: pronunciation,
            onConfirm: onConfirm,
            onDismiss: { [weak self] in self?.dismiss(animated: true) },
            onSizeChange: { [weak self] height, headerHeight in
                guard let self else { return }
                self.headerHeight = headerHeight
                guard contentHeight != height else { return }
                contentHeight = height
                preferredContentSize.height = height
            }
        )
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(AddCardColors.background)
        view.layer.cornerRadius = 24
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    func prepareForPresentation(in window: UIWindow) {
        // Resolve SwiftUI's initial measurements before UIKit starts the transition.
        loadViewIfNeeded()
        view.frame = CGRect(x: 0, y: 0, width: window.bounds.width,
                            height: window.bounds.height - window.safeAreaInsets.top - 8)
        rootView.measuresContent = true
        let size = sizeThatFits(in: CGSize(width: window.bounds.width, height: .greatestFiniteMagnitude))
        rootView.measuresContent = false
        contentHeight = size.height
        preferredContentSize = size
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              !isBeingPresented, !isBeingDismissed else { return false }
        let velocity = pan.velocity(in: view.superview)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        draggedScrollView = scrollView(at: pan.location(in: view))
        // Let the list keep scrolling while a previous drawer drag settles.
        if draggedScrollView != nil, returnAnimator != nil { return false }
        return pan.location(in: view).y <= headerHeight || draggedScrollView != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other === draggedScrollView?.panGestureRecognizer
    }

    private func scrollView(at point: CGPoint) -> UIScrollView? {
        var candidate = view.hitTest(point, with: nil)
        while let current = candidate, current !== view {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled { return scroll }
            candidate = current.superview
        }
        return nil
    }

    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        // Measure in the stationary container: the drawer itself stretches and moves.
        let translation = pan.translation(in: view.superview).y
        let velocity = pan.velocity(in: view.superview).y
        switch pan.state {
        case .began:
            stopReturnAnimation()
            dragOrigin = 0
            dragStartOffset = unresistedOffset()
            hasTakenOverScroll = draggedScrollView == nil
            updateDrag(translation: translation, velocity: velocity)
        case .changed:
            updateDrag(translation: translation, velocity: velocity)
        case .ended:
            let wasDraggingDrawer = hasTakenOverScroll
            restoreScrolling()
            guard wasDraggingDrawer else { return }
            let projectedDistance = dragOffset + velocity * 0.15
            if dragOffset > 0, velocity >= 0,
               projectedDistance > min(180, view.bounds.height * 0.4) {
                dismissalVelocity = velocity
                dismiss(animated: true)
            } else {
                springBack(velocity: velocity)
            }
        case .cancelled, .failed:
            let wasDraggingDrawer = hasTakenOverScroll
            restoreScrolling()
            if wasDraggingDrawer { springBack(velocity: 0) }
        default:
            break
        }
    }

    private func updateDrag(translation: CGFloat, velocity: CGFloat) {
        if let scroll = draggedScrollView, !hasTakenOverScroll {
            let top = -scroll.adjustedContentInset.top
            guard scroll.contentOffset.y <= top + 0.5, velocity > 0 else { return }
            // Transfer ownership once. Cancelling the scroll view's pan stops its
            // bounce/deceleration; only the drawer writes positions from here on.
            // Keep that ownership until finger-up, including direction reversals.
            hasTakenOverScroll = true
            // Preserve any top overscroll already displayed by the list.
            dragOrigin = translation - max(0, top - scroll.contentOffset.y)
            scroll.isScrollEnabled = false
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: false)
        }
        let distance = dragStartOffset + translation - dragOrigin
        applyDrag(draggedScrollView == nil ? distance : max(0, distance))
    }

    private var stretchLimit: CGFloat { min(48, view.bounds.height * 0.1) }

    private func applyDrag(_ distance: CGFloat) {
        if distance < 0 {
            // Asymptotic resistance, anchored at the bottom. X scale stays exactly 1.
            let stretch = stretchLimit * (-distance * 0.55) / (stretchLimit - distance * 0.55)
            dragOffset = -stretch
            view.transform = CGAffineTransform(a: 1, b: 0, c: 0,
                                               d: 1 + stretch / view.bounds.height,
                                               tx: 0, ty: -stretch / 2)
        } else {
            dragOffset = distance
            view.transform = CGAffineTransform(translationX: 0, y: distance)
        }
        drawerPresentation?.setDragProgress(max(0, dragOffset) / view.bounds.height)
    }

    private func unresistedOffset() -> CGFloat {
        let transform = view.transform
        let offset = transform.ty - (transform.d - 1) * view.bounds.height / 2
        guard offset < 0 else { return offset }
        let stretch = min(-offset, stretchLimit - 0.01)
        return -stretch * stretchLimit / (0.55 * (stretchLimit - stretch))
    }

    private func restoreScrolling() {
        if let scroll = draggedScrollView, hasTakenOverScroll { scroll.isScrollEnabled = true }
        draggedScrollView = nil
        hasTakenOverScroll = false
    }

    private func stopReturnAnimation() {
        guard let animator = returnAnimator else { return }
        let transform = view.layer.presentation()?.affineTransform() ?? view.transform
        animator.stopAnimation(true)
        returnAnimator = nil
        view.transform = transform
        dragOffset = transform.ty - (transform.d - 1) * view.bounds.height / 2
        drawerPresentation?.setDragProgress(max(0, dragOffset) / view.bounds.height)
    }

    private func springBack(velocity: CGFloat) {
        // Rubber resistance reduces both displacement and visible velocity.
        let resistance = dragOffset < 0 ? 0.55 * pow(1 + dragOffset / stretchLimit, 2) : 1
        let normalizedVelocity = abs(dragOffset) > 1 ? velocity * resistance / -dragOffset : 0
        let timing = UISpringTimingParameters(
            // A translated drawer must stop at its resting edge; the stretched
            // transform can rebound while keeping its bottom anchored.
            dampingRatio: dragOffset > 0 ? 1 : 0.82,
            initialVelocity: CGVector(dx: 0, dy: max(-12, min(12, normalizedVelocity)))
        )
        // Spring settling is separate from the 140 ms presentation/dismissal.
        let animator = UIViewPropertyAnimator(duration: 0.32, timingParameters: timing)
        animator.addAnimations { [weak self] in
            self?.view.transform = .identity
            self?.drawerPresentation?.setDragProgress(0)
        }
        animator.addCompletion { [weak self] _ in
            self?.returnAnimator = nil
            self?.dragOffset = 0
        }
        returnAnimator = animator
        animator.startAnimation()
    }

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?, source: UIViewController)
        -> UIPresentationController? {
        DrawerPresentationController(presentedViewController: presented,
                                     presenting: presenting, onDismiss: didDismiss)
    }

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController, source: UIViewController)
        -> (any UIViewControllerAnimatedTransitioning)? {
        DrawerAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController)
        -> (any UIViewControllerAnimatedTransitioning)? {
        stopReturnAnimation()
        let animator = DrawerAnimator(presenting: false, releaseVelocity: dismissalVelocity)
        dismissalVelocity = 0
        return animator
    }
}

private final class DrawerPresentationController: UIPresentationController {
    private let dimmingView = UIView()
    private let onDismiss: () -> Void

    init(presentedViewController: UIViewController, presenting: UIViewController?,
         onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(presentedViewController: presentedViewController, presenting: presenting)
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
    }

    override var shouldRemovePresentersView: Bool { false }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bounds = containerView.bounds
        let maximumHeight = bounds.height - containerView.safeAreaInsets.top - 8
        let contentHeight = presentedViewController.preferredContentSize.height
        let height = contentHeight > 0
            ? min(contentHeight + containerView.safeAreaInsets.bottom, maximumHeight)
            : maximumHeight
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let containerView, let presentedView else { return }
        dimmingView.frame = containerView.bounds
        let frame = frameOfPresentedViewInContainerView
        // Bounds/center preserve the animator's vertical translation during layout.
        if presentedView.bounds.size != frame.size { presentedView.bounds.size = frame.size }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if presentedView.center != center { presentedView.center = center }
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        containerView?.setNeedsLayout()
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        dimmingView.frame = containerView.bounds
        dimmingView.alpha = 0
        containerView.insertSubview(dimmingView, at: 0)
        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in self.dimmingView.alpha = 1 })
        } else {
            dimmingView.alpha = 1
        }
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        if !completed { dimmingView.removeFromSuperview() }
    }

    override func dismissalTransitionWillBegin() {
        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in self.dimmingView.alpha = 0 })
        } else {
            dimmingView.alpha = 0
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimmingView.removeFromSuperview()
            onDismiss()
        } else {
            dimmingView.alpha = 1
        }
    }

    func setDragProgress(_ progress: CGFloat) {
        dimmingView.alpha = 1 - min(1, max(0, progress))
    }

    @objc private func close() {
        presentedViewController.dismiss(animated: true)
    }
}

private final class DrawerAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    private let releaseVelocity: CGFloat
    private var animator: UIViewPropertyAnimator?

    init(presenting: Bool, releaseVelocity: CGFloat = 0) {
        self.presenting = presenting
        self.releaseVelocity = releaseVelocity
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.14
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: context).startAnimation()
    }

    func interruptibleAnimator(using context: any UIViewControllerContextTransitioning)
        -> any UIViewImplicitlyAnimating {
        if let animator { return animator }
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key),
              let drawer = context.view(forKey: presenting ? .to : .from) else {
            let animator = UIViewPropertyAnimator(duration: 0, curve: .linear)
            animator.addCompletion { _ in context.completeTransition(false) }
            self.animator = animator
            return animator
        }
        if presenting {
            drawer.frame = context.finalFrame(for: controller)
            context.containerView.addSubview(drawer)
        }
        // A dismissal starts at the current dragged position, with the finger's
        // velocity normalized by the remaining travel, not the full sheet height.
        let restingFrame = controller.presentationController?.frameOfPresentedViewInContainerView
            ?? drawer.frame
        let hidden = CGAffineTransform(translationX: 0,
                                      y: context.containerView.bounds.maxY - restingFrame.minY)
        if presenting { drawer.transform = hidden }
        let animator: UIViewPropertyAnimator
        if !presenting, releaseVelocity > 0 {
            let remainingDistance = hidden.ty - drawer.transform.ty
            let velocity = remainingDistance > 1 ? releaseVelocity / remainingDistance : 0
            let timing = UISpringTimingParameters(dampingRatio: 1,
                                                 initialVelocity: CGVector(dx: 0, dy: velocity))
            animator = UIViewPropertyAnimator(duration: transitionDuration(using: context),
                                              timingParameters: timing)
        } else {
            animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), curve: .easeOut)
        }
        animator.addAnimations {
            drawer.transform = self.presenting ? .identity : hidden
        }
        animator.addCompletion { _ in
            let completed = !context.transitionWasCancelled
            if self.presenting ? !completed : completed { drawer.removeFromSuperview() }
            drawer.transform = .identity
            context.completeTransition(completed)
        }
        self.animator = animator
        return animator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        animator = nil
    }
}
