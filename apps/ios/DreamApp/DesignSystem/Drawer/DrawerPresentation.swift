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
/// modal: custom UIKit presentation with drag-to-dismiss.
///
/// The owning controller creates one, calls `attach(to:)` from `viewDidLoad`,
/// and reports its content height as SwiftUI measures it.
///
/// The drawer is anchored to the bottom and moves by changing its height:
/// free between closed and its last detent, then stretching past it with
/// diminishing give. Dragging the header moves it; a drag inside a scroll
/// view moves it while the list sits at its top and the drawer has room to
/// grow, and the two never write offsets during the same drag. A release
/// settles on a clamped spring that inherits the finger's velocity and stops
/// dead on its detent: a downward fling or a pull past a quarter of the base
/// height dismisses, flings between detents override proximity, and anything
/// else goes to the nearer detent. Presentation slides in over 150 ms; the
/// close button slides out over 200 ms.
@MainActor
final class DrawerPresentation: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
    var appearance: DrawerAppearance
    /// The zone a drag may start in outside any scroll view.
    var headerHeight: CGFloat = 81
    private(set) var contentHeight: CGFloat = 0

    private unowned let controller: UIViewController
    private let onDismiss: () -> Void
    private var settle: SpringSettle?
    private weak var draggedScrollView: UIScrollView?
    /// The finger's downward speed, handed to the dismissal transition.
    private var dismissalVelocity: CGFloat = 0
    private var hasTakenOverScroll = false
    /// Where the finger's translation counts from once the drawer owns the drag.
    private var dragOrigin: CGFloat = 0
    /// The height at the start of the drag with the stretch resistance undone.
    private var dragStartHeight: CGFloat = 0

    private var view: UIView { controller.view }

    private var presentationController: DrawerPresentationController? {
        controller.presentationController as? DrawerPresentationController
    }

    private var height: CGFloat { presentationController?.currentHeight ?? view.bounds.height }
    private var baseHeight: CGFloat { presentationController?.baseHeight ?? 0 }
    private var expandedHeight: CGFloat { presentationController?.expandedHeight ?? 0 }
    private var maximumHeight: CGFloat { presentationController?.maximumHeight ?? 0 }

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
        // The drawer moves instead of the list rubber-banding at either end.
        draggedScrollView?.bounces = false
        // A list scrolled away from its top keeps scrolling while the drawer settles.
        if let scroll = draggedScrollView, settle != nil, !isAtTop(scroll) { return false }
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

    private func isAtTop(_ scroll: UIScrollView) -> Bool {
        scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 0.5
    }

    private func isScrollable(_ scroll: UIScrollView) -> Bool {
        let inset = scroll.adjustedContentInset
        return scroll.contentSize.height > scroll.bounds.height - inset.top - inset.bottom + 1
    }

    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        // Measure in the stationary container: the drawer itself moves.
        let translation = pan.translation(in: view.superview).y
        let velocity = pan.velocity(in: view.superview).y
        switch pan.state {
        case .began:
            stopSettling()
            dragOrigin = 0
            dragStartHeight = unresistedHeight()
            hasTakenOverScroll = draggedScrollView == nil
            updateDrag(translation: translation, velocity: velocity)
        case .changed:
            updateDrag(translation: translation, velocity: velocity)
        case .ended:
            let wasDraggingDrawer = hasTakenOverScroll
            restoreScrolling()
            guard wasDraggingDrawer else { return }
            release(velocity: velocity)
        case .cancelled, .failed:
            let wasDraggingDrawer = hasTakenOverScroll
            restoreScrolling()
            if wasDraggingDrawer { release(velocity: 0) }
        default:
            break
        }
    }

    private func updateDrag(translation: CGFloat, velocity: CGFloat) {
        var clampsAtDetent = false
        if let scroll = draggedScrollView {
            let scrollable = isScrollable(scroll)
            // A scrollable list takes the drag back at the last detent; content
            // with nothing to scroll stretches past it like the header.
            clampsAtDetent = scrollable
            if !hasTakenOverScroll {
                guard isAtTop(scroll) else { return }
                // At the top of the list, a pull down moves the drawer and a push
                // up grows it while it has room.
                guard velocity > 0 || (velocity < 0 && (height < expandedHeight || !scrollable)) else { return }
                // Transfer ownership once. Cancelling the scroll view's pan stops its
                // deceleration; only the drawer writes positions from here on.
                // Keep that ownership until finger-up, including direction reversals.
                hasTakenOverScroll = true
                let top = -scroll.adjustedContentInset.top
                // Preserve any top overscroll already displayed by the list.
                dragOrigin = translation - max(0, top - scroll.contentOffset.y)
                scroll.isScrollEnabled = false
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: false)
            }
        }
        let raw = dragStartHeight - (translation - dragOrigin)
        applyHeight(clampsAtDetent ? min(max(raw, 0), expandedHeight) : resistedHeight(raw))
    }

    private func applyHeight(_ height: CGFloat) {
        guard let presentationController else { return }
        presentationController.dragHeight = height
        presentationController.containerView?.layoutIfNeeded()
        presentationController.setDragProgress(1 - min(1, height / max(baseHeight, 1)))
    }

    /// Maps the finger's unclamped height to the drawer's: free between
    /// closed and the last detent, then diminishing give past it, flattening
    /// out at the stretch limit.
    private func resistedHeight(_ raw: CGFloat) -> CGFloat {
        guard raw > expandedHeight else { return max(raw, 0) }
        let overshoot = raw - expandedHeight
        let limit = DrawerMotion.stretchLimit
        let give = (1 - 1 / (overshoot * DrawerMotion.rubberCoefficient / limit + 1)) * limit
        return min(expandedHeight + give, maximumHeight)
    }

    /// The current height with the stretch resistance undone.
    private func unresistedHeight() -> CGFloat {
        let height = height
        guard height > expandedHeight else { return height }
        let limit = DrawerMotion.stretchLimit
        let give = min(height - expandedHeight, limit - 0.01)
        let overshoot = (1 / (1 - give / limit) - 1) * limit / DrawerMotion.rubberCoefficient
        return expandedHeight + overshoot
    }

    private func restoreScrolling() {
        if let scroll = draggedScrollView, hasTakenOverScroll { scroll.isScrollEnabled = true }
        draggedScrollView = nil
        hasTakenOverScroll = false
    }

    /// Catches a settling drawer where it is; the next drag continues from there.
    private func stopSettling() {
        settle?.stop()
        settle = nil
    }

    /// The release rule: dismiss on a downward fling or a deep pull, otherwise
    /// snap to a detent, with flings overriding proximity.
    private func release(velocity: CGFloat) {
        let current = height
        let flingDown = velocity > DrawerMotion.flingVelocity
        let flingUp = velocity < -DrawerMotion.flingVelocity
        let target: CGFloat
        if current <= baseHeight {
            let dismisses = flingDown || current < baseHeight * (1 - DrawerMotion.dismissDistanceRatio)
            target = dismisses ? 0 : baseHeight
        } else if flingUp {
            target = expandedHeight
        } else if flingDown {
            target = baseHeight
        } else {
            target = current > (baseHeight + expandedHeight) / 2 ? expandedHeight : baseHeight
        }
        if target == 0 {
            dismissalVelocity = max(0, velocity)
            controller.dismiss(animated: true)
            return
        }
        // A rubber-band release lands here too: the midpoint rule picks the
        // expanded detent. The finger's speed is the height's, sign flipped.
        let detent: DrawerPresentationController.Detent = target > baseHeight ? .expanded : .base
        settle = SpringSettle(from: current, to: target, velocity: -velocity) { [weak self] height in
            self?.applyHeight(height)
        } completion: { [weak self] in
            guard let self, let presentationController else { return }
            settle = nil
            presentationController.detent = detent
            presentationController.dragHeight = nil
        }
        settle?.start()
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
        stopSettling()
        let animator = DrawerAnimator(presenting: false, releaseVelocity: dismissalVelocity)
        dismissalVelocity = 0
        return animator
    }
}

/// The drawer's motion constants.
private enum DrawerMotion {
    static let openDuration: TimeInterval = 0.15
    /// Programmatic close: the button or a tap outside, with no finger velocity.
    static let closeDuration: TimeInterval = 0.2
    /// About how long the release spring takes to come to rest; the transition
    /// coordinator uses it for animations that run alongside a dismissal.
    static let releaseDuration: TimeInterval = 0.45
    /// A release faster than this dismisses or changes detent regardless of
    /// how far the drawer has moved.
    static let flingVelocity: CGFloat = 900
    /// A pull past this fraction of the base height dismisses on release.
    static let dismissDistanceRatio: CGFloat = 0.25
    /// Extra travel past the screen edge on dismissal.
    static let exitOvershoot: CGFloat = 24
    /// Resistance past the last detent, and the asymptotic cap on the stretch:
    /// a tight hint of elasticity, never a chase to the top of the screen.
    static let rubberCoefficient: CGFloat = 0.55
    static let stretchLimit: CGFloat = 64
    /// The release spring: mass 1, damping ratio 1.04, so it never bounces.
    static let springStiffness: CGFloat = 300
    static let springDamping: CGFloat = 36

    /// The dismissal transition's spring, from the finger's speed. `distance`
    /// is the signed travel to the target.
    static func releaseSpring(velocity: CGFloat, over distance: CGFloat) -> UISpringTimingParameters {
        // UIKit takes the velocity in travel distances per second, signed toward the target.
        let normalized = abs(distance) > 1 ? velocity / distance : 0
        return UISpringTimingParameters(mass: 1, stiffness: springStiffness, damping: springDamping,
                                        initialVelocity: CGVector(dx: 0, dy: normalized))
    }
}

/// Drives a value to a target on the release spring, frame by frame, and
/// clamps at the target: it glides in at the speed it was released, stops
/// dead, and never overshoots. Stopping leaves the value where it is.
@MainActor
private final class SpringSettle {
    private var link: CADisplayLink?
    private var position: CGFloat
    private var velocity: CGFloat
    private let target: CGFloat
    private let step: (CGFloat) -> Void
    private let completion: () -> Void

    init(from position: CGFloat, to target: CGFloat, velocity: CGFloat,
         step: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        self.position = position
        self.velocity = velocity
        self.target = target
        self.step = step
        self.completion = completion
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let startedBelow = position < target
        // Semi-implicit Euler in millisecond substeps: stable and accurate at
        // this stiffness, and independent of the display's refresh rate.
        var remaining = min(link.targetTimestamp - link.timestamp, 1 / 30)
        while remaining > 0 {
            let dt = min(remaining, 0.001)
            let acceleration = -DrawerMotion.springStiffness * (position - target)
                - DrawerMotion.springDamping * velocity
            velocity += acceleration * dt
            position += velocity * dt
            remaining -= dt
        }
        let crossed = startedBelow ? position >= target : position <= target
        let atRest = abs(velocity) < 2 && abs(position - target) < 0.01
        if crossed || atRest {
            stop()
            step(target)
            completion()
        } else {
            step(position)
        }
    }
}

private final class DrawerPresentationController: UIPresentationController {
    enum Detent {
        case base
        case expanded
    }

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

    /// The detent the drawer rests at.
    var detent: Detent = .base {
        didSet { if oldValue != detent { containerView?.setNeedsLayout() } }
    }

    /// The height while a drag or a settle owns it; `nil` rests at the detent.
    var dragHeight: CGFloat? {
        didSet { if oldValue != dragHeight { containerView?.setNeedsLayout() } }
    }

    override var shouldRemovePresentersView: Bool { false }

    var maximumHeight: CGFloat {
        guard let containerView else { return 0 }
        return containerView.bounds.height - containerView.safeAreaInsets.top - 8
    }

    var baseHeight: CGFloat {
        guard let containerView else { return 0 }
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

    /// The last detent: the expanded one when there is one, else the base.
    var expandedHeight: CGFloat {
        guard let containerView, case .anchored(_, let fraction?) = appearance.height else { return baseHeight }
        return min(max(containerView.bounds.height * fraction, baseHeight), maximumHeight)
    }

    var currentHeight: CGFloat {
        dragHeight ?? (detent == .expanded ? expandedHeight : baseHeight)
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bounds = containerView.bounds
        let height = min(currentHeight, maximumHeight)
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard let containerView, let presentedView else { return }
        dimmingView.frame = containerView.bounds
        let frame = frameOfPresentedViewInContainerView
        // Bounds/center preserve the transition's vertical translation during layout.
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

    /// `progress` runs from 0 at the base detent to 1 at fully closed.
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
        if presenting { return DrawerMotion.openDuration }
        return releaseVelocity > 0 ? DrawerMotion.releaseDuration : DrawerMotion.closeDuration
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
        // A dismissal slides from wherever the drag left the drawer, and
        // overshoots the edge by the corner radius so the slow end of the
        // motion happens off screen instead of the rim lingering at the edge.
        let restingFrame = controller.presentationController?.frameOfPresentedViewInContainerView
            ?? drawer.frame
        let offScreen = context.containerView.bounds.maxY - restingFrame.minY
        let hidden = CGAffineTransform(translationX: 0, y: offScreen + (presenting ? 0 : DrawerMotion.exitOvershoot))
        if presenting { drawer.transform = hidden }
        let animator: UIViewPropertyAnimator
        if !presenting, releaseVelocity > 0 {
            let remainingDistance = hidden.ty - drawer.transform.ty
            animator = UIViewPropertyAnimator(
                duration: 0, // A physical spring runs until it settles.
                timingParameters: DrawerMotion.releaseSpring(velocity: releaseVelocity, over: remainingDistance)
            )
        } else {
            animator = UIViewPropertyAnimator(duration: transitionDuration(using: context),
                                              curve: presenting ? .easeOut : .easeInOut)
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
