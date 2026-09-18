import UIKit

/// How a drawer sizes itself in its container.
enum DrawerHeight {
    /// The content's natural height plus bottom safe-area clearance, capped
    /// below the top safe area.
    case content
    /// The top edge sits at this window Y. Content taller than that scrolls.
    /// With `expandedFraction`, an upward drag grows the drawer to that
    /// fraction of the container's height, a second detent it snaps to.
    case anchored(top: CGFloat, expandedFraction: CGFloat? = nil)
}

struct DrawerAppearance {
    var backgroundColor: UIColor
    var cornerRadius: CGFloat = 24
    /// Dims the presenting screen. Off, the screen stays as it was, though a
    /// tap on it still dismisses the drawer.
    var dimsPresenter = true
    var height: DrawerHeight = .content
}

/// A bottom drawer presented over the current screen without a SwiftUI
/// modal: custom UIKit presentation, a 140 ms slide, and drag-to-dismiss.
///
/// The owning controller creates one, calls `attach(to:)` from `viewDidLoad`,
/// and reports its content height as SwiftUI measures it. Dragging the
/// header moves the drawer; dragging inside a scroll view hands the drag to
/// the drawer only once the list is at its top, and the two never write
/// offsets during the same drag. Upward drags grow the drawer to its expanded
/// detent when it has one, then stretch with resistance; release springs to
/// the nearest detent. A downward flick or a long pull dismisses with the
/// release velocity.
@MainActor
final class DrawerPresentation: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
    var appearance: DrawerAppearance
    /// The zone a drag may start in outside any scroll view.
    var headerHeight: CGFloat = 81
    private(set) var contentHeight: CGFloat = 0

    private unowned let controller: UIViewController
    private let onDismiss: () -> Void
    private var returnAnimator: UIViewPropertyAnimator?
    private weak var draggedScrollView: UIScrollView?
    private var dismissalVelocity: CGFloat = 0
    private var hasTakenOverScroll = false
    private var dragOrigin: CGFloat = 0
    private var dragStartOffset: CGFloat = 0
    private var dragOffset: CGFloat = 0

    private var view: UIView { controller.view }

    private var presentationController: DrawerPresentationController? {
        controller.presentationController as? DrawerPresentationController
    }

    /// Height added above the base detent right now.
    private var detentExtension: CGFloat { presentationController?.detentExtension ?? 0 }

    /// How much taller the expanded detent is than the base; zero without one.
    private var expandedExtension: CGFloat { presentationController?.expandedExtension ?? 0 }

    /// `onDismiss` runs once a dismissal, from any cause, has completed.
    init(controller: UIViewController, appearance: DrawerAppearance, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.appearance = appearance
        self.onDismiss = onDismiss
        super.init()
        controller.modalPresentationStyle = .custom
        controller.transitioningDelegate = self
    }

    /// Styles the drawer's view and installs the drag gesture.
    func attach(to view: UIView) {
        view.backgroundColor = appearance.backgroundColor
        view.layer.cornerRadius = appearance.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    func setContentHeight(_ height: CGFloat) {
        guard contentHeight != height else { return }
        contentHeight = height
        controller.preferredContentSize.height = height
    }

    /// Lays the view out at the presentation width so SwiftUI's initial
    /// measurements resolve before UIKit starts the transition. `measure`
    /// returns the content's natural size.
    func prepareForPresentation(in window: UIWindow, measure: () -> CGSize) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: window.bounds.width,
                                       height: window.bounds.height - window.safeAreaInsets.top - 8)
        let size = measure()
        contentHeight = size.height
        controller.preferredContentSize = size
    }

    // MARK: - Dragging

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              !controller.isBeingPresented, !controller.isBeingDismissed else { return false }
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
                controller.dismiss(animated: true)
            } else {
                settle(velocity: velocity)
            }
        case .cancelled, .failed:
            let wasDraggingDrawer = hasTakenOverScroll
            restoreScrolling()
            if wasDraggingDrawer { settle(velocity: 0) }
        default:
            break
        }
    }

    private func updateDrag(translation: CGFloat, velocity: CGFloat) {
        if let scroll = draggedScrollView, !hasTakenOverScroll {
            let top = -scroll.adjustedContentInset.top
            guard scroll.contentOffset.y <= top + 0.5 else { return }
            // At the top of the list, a pull down moves the drawer and a push
            // up grows it toward the expanded detent.
            guard velocity > 0 || (velocity < 0 && detentExtension < expandedExtension) else { return }
            // Transfer ownership once. Cancelling the scroll view's pan stops its
            // bounce/deceleration; only the drawer writes positions from here on.
            // Keep that ownership until finger-up, including direction reversals.
            hasTakenOverScroll = true
            // Preserve any top overscroll already displayed by the list.
            dragOrigin = translation - max(0, top - scroll.contentOffset.y)
            scroll.isScrollEnabled = false
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: false)
        }
        let position = dragStartOffset + translation - dragOrigin
        // A drag begun in the list never stretches past the last detent.
        applyDrag(draggedScrollView == nil ? position : max(-expandedExtension, position))
    }

    private var stretchLimit: CGFloat { min(48, view.bounds.height * 0.1) }

    /// Positions the drawer for a signed drag offset: positive moves it down
    /// toward dismissal; negative raises it through the expanded detent, then
    /// stretches it with resistance.
    private func applyDrag(_ position: CGFloat) {
        dragOffset = position
        if position < 0 {
            let raise = -position
            let lift = min(raise, expandedExtension)
            let overshoot = raise - lift
            // Asymptotic resistance, anchored at the bottom. X scale stays exactly 1.
            let stretch = stretchLimit * (overshoot * 0.55) / (stretchLimit + overshoot * 0.55)
            setDetentExtension(lift)
            view.transform = CGAffineTransform(a: 1, b: 0, c: 0,
                                               d: 1 + stretch / view.bounds.height,
                                               tx: 0, ty: -stretch / 2)
        } else {
            setDetentExtension(0)
            view.transform = CGAffineTransform(translationX: 0, y: position)
        }
        presentationController?.setDragProgress(max(0, position) / view.bounds.height)
    }

    private func setDetentExtension(_ height: CGFloat) {
        guard let presentationController, presentationController.detentExtension != height else { return }
        presentationController.detentExtension = height
        presentationController.containerView?.layoutIfNeeded()
    }

    /// The signed drag offset the current detent and transform represent,
    /// with the stretch resistance undone.
    private func unresistedOffset() -> CGFloat {
        let transform = view.transform
        let offset = transform.ty - (transform.d - 1) * view.bounds.height / 2
        guard offset <= 0 else { return offset }
        let stretch = min(-offset, stretchLimit - 0.01)
        let overshoot = stretch * stretchLimit / (0.55 * (stretchLimit - stretch))
        return -(detentExtension + overshoot)
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
        // The detent lands where the animation was heading; only the
        // transform continues from where the finger caught it.
        presentationController?.containerView?.layoutIfNeeded()
        view.transform = transform
        dragOffset = unresistedOffset()
        presentationController?.setDragProgress(max(0, dragOffset) / view.bounds.height)
    }

    /// Springs to the nearest detent with the finger's velocity: the base
    /// detent, or the expanded one when the projected release lands closer
    /// to it.
    private func settle(velocity: CGFloat) {
        let projected = dragOffset + velocity * 0.15
        let target = expandedExtension > 0 && projected < -expandedExtension / 2 ? -expandedExtension : 0
        let travel = target - dragOffset
        // Rubber resistance reduces both displacement and visible velocity.
        let stretch = (view.transform.d - 1) * view.bounds.height
        let resistance = stretch > 0 ? 0.55 * pow(1 - stretch / stretchLimit, 2) : 1
        let normalizedVelocity = abs(travel) > 1 ? velocity * resistance / travel : 0
        let timing = UISpringTimingParameters(
            // A moving drawer must stop at its detent; the stretched
            // transform can rebound while keeping its bottom anchored.
            dampingRatio: stretch > 0 ? 0.82 : 1,
            initialVelocity: CGVector(dx: 0, dy: max(-12, min(12, normalizedVelocity)))
        )
        // Spring settling is separate from the 140 ms presentation/dismissal.
        let animator = UIViewPropertyAnimator(duration: 0.32, timingParameters: timing)
        animator.addAnimations { [weak self] in
            guard let self else { return }
            setDetentExtension(-target)
            view.transform = .identity
            presentationController?.setDragProgress(0)
        }
        animator.addCompletion { [weak self] _ in
            self?.returnAnimator = nil
            self?.dragOffset = target
        }
        returnAnimator = animator
        animator.startAnimation()
    }

    // MARK: - Transitioning

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?, source: UIViewController)
        -> UIPresentationController? {
        DrawerPresentationController(presentedViewController: presented, presenting: presenting,
                                     appearance: appearance, onDismiss: onDismiss)
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
    private let appearance: DrawerAppearance
    private let onDismiss: () -> Void

    init(presentedViewController: UIViewController, presenting: UIViewController?,
         appearance: DrawerAppearance, onDismiss: @escaping () -> Void) {
        self.appearance = appearance
        self.onDismiss = onDismiss
        super.init(presentedViewController: presentedViewController, presenting: presenting)
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(appearance.dimsPresenter ? 0.4 : 0)
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
    }

    /// Height added above the base detent, up to `expandedExtension`.
    var detentExtension: CGFloat = 0 {
        didSet { if oldValue != detentExtension { containerView?.setNeedsLayout() } }
    }

    override var shouldRemovePresentersView: Bool { false }

    /// How much taller the expanded detent is than the base; zero without one.
    var expandedExtension: CGFloat {
        guard let containerView, case .anchored(_, let fraction?) = appearance.height else { return 0 }
        let expanded = min(containerView.bounds.height * fraction, maximumHeight(in: containerView))
        return max(0, expanded - baseHeight(in: containerView))
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bounds = containerView.bounds
        let height = min(baseHeight(in: containerView) + detentExtension, maximumHeight(in: containerView))
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }

    private func maximumHeight(in containerView: UIView) -> CGFloat {
        containerView.bounds.height - containerView.safeAreaInsets.top - 8
    }

    private func baseHeight(in containerView: UIView) -> CGFloat {
        let maximumHeight = maximumHeight(in: containerView)
        switch appearance.height {
        case .content:
            let contentHeight = presentedViewController.preferredContentSize.height
            return contentHeight > 0
                ? min(contentHeight + containerView.safeAreaInsets.bottom, maximumHeight)
                : maximumHeight
        case .anchored(let top, _):
            return min(max(containerView.bounds.maxY - top, 120), maximumHeight)
        }
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
