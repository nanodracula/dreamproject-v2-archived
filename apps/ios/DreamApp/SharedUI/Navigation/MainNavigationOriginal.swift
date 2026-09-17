import UIKit

/// Native glass with two independently retargetable springs, in slot coordinates.
final class MainNavigationOriginal: UIView, MainNavigationBar {
    let metrics = MainNavigationMetrics(height: 58, sideInset: 32)
    var selectionChanged: ((Int) -> Void)?
    private let glass: UIVisualEffectView
    private let pill = UIView()
    private var buttons: [UIButton] = []
    private var glyphs: [(idle: UIImageView, active: UIImageView)] = []
    private var leading = EdgeSpring(value: 0)
    private var trailing = EdgeSpring(value: 1)
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var selectedIndex = 0

    init(items: [MainNavigationItem]) {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        glass = UIVisualEffectView(effect: effect)
        super.init(frame: .zero)
        addSubview(glass)
        glass.clipsToBounds = true
        pill.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        pill.isUserInteractionEnabled = false
        glass.contentView.addSubview(pill)
        let configuration = UIImage.SymbolConfiguration(pointSize: 23, weight: .regular)
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.accessibilityLabel = item.title
            button.addAction(UIAction { [weak self] _ in self?.selectionChanged?(index) }, for: .touchUpInside)
            let idle = UIImageView(image: UIImage(systemName: item.symbol, withConfiguration: configuration))
            let active = UIImageView(image: UIImage(systemName: item.selectedSymbol, withConfiguration: configuration))
            idle.tintColor = UIColor(red: 176 / 255, green: 180 / 255, blue: 186 / 255, alpha: 1)
            active.tintColor = UIColor(red: 233 / 255, green: 236 / 255, blue: 239 / 255, alpha: 1)
            for image in [idle, active] {
                image.contentMode = .scaleAspectFit
                image.isUserInteractionEnabled = false
                button.addSubview(image)
            }
            glass.contentView.addSubview(button)
            buttons.append(button)
            glyphs.append((idle, active))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit { displayLink?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.isPaused = true
        } else if !leading.isSettled || !trailing.isSettled {
            animate()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glass.layer.cornerRadius = bounds.height / 2
        let content = bounds.insetBy(dx: 7, dy: 7)
        let width = content.width / CGFloat(max(buttons.count, 1))
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: content.minX + CGFloat(index) * width, y: content.minY, width: width, height: content.height)
            let frame = CGRect(x: (width - 23) / 2, y: (content.height - 23) / 2, width: 23, height: 23)
            glyphs[index].idle.frame = frame
            glyphs[index].active.frame = frame
        }
        updatePresentation()
    }

    func select(_ index: Int, animated: Bool) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        let forward = CGFloat(index) > (leading.value + trailing.value) / 2 - 0.5
        leading.retarget(CGFloat(index), fast: !forward)
        trailing.retarget(CGFloat(index + 1), fast: forward)
        if !animated || UIAccessibility.isReduceMotionEnabled {
            leading.finish()
            trailing.finish()
            displayLink?.isPaused = true
        } else {
            animate()
        }
        updatePresentation()
    }

    private func animate() {
        if displayLink == nil {
            displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] delta in
                self?.step(delta)
            }
        }
        displayLink?.isPaused = window == nil
    }

    private func step(_ delta: CGFloat) {
        // Small integration steps keep the same spring stable at either 60 or 120 Hz.
        var remaining = min(delta, 1 / 15)
        while remaining > 0 {
            let step = min(remaining, 1 / 240)
            leading.step(step)
            trailing.step(step)
            remaining -= step
        }
        updatePresentation()
        if leading.isSettled && trailing.isSettled { displayLink?.isPaused = true }
    }

    private func updatePresentation() {
        let content = bounds.insetBy(dx: 7, dy: 7)
        let width = content.width / CGFloat(max(buttons.count, 1))
        let center = (leading.value + trailing.value) / 2
        let pillWidth = max(0.01, trailing.value - leading.value) * width
        pill.frame = CGRect(x: content.minX + center * width - pillWidth / 2, y: content.minY, width: pillWidth, height: content.height)
        pill.layer.cornerRadius = content.height / 2
        for (index, glyph) in glyphs.enumerated() {
            let fill = max(0, 1 - abs(center - 0.5 - CGFloat(index)))
            glyph.active.alpha = fill
            glyph.idle.alpha = 1 - fill
            buttons[index].accessibilityTraits = index == selectedIndex ? [.button, .selected] : [.button]
        }
    }
}

private struct EdgeSpring {
    var value: CGFloat
    private var velocity: CGFloat = 0
    private var target: CGFloat
    private var mass: CGFloat = 0.9
    private var stiffness: CGFloat = 240
    private var damping: CGFloat = 28

    init(value: CGFloat) { self.value = value; target = value }

    var isSettled: Bool { abs(value - target) < 0.0001 && abs(velocity) < 0.001 }

    mutating func retarget(_ target: CGFloat, fast: Bool) {
        self.target = target
        mass = fast ? 0.7 : 0.9
        stiffness = fast ? 400 : 240
        damping = fast ? 30 : 28
        // Keep both the current position and velocity when direction changes.
    }

    mutating func step(_ delta: CGFloat) {
        velocity += (-stiffness * (value - target) - damping * velocity) / mass * delta
        value += velocity * delta
        if isSettled { finish() }
    }

    mutating func finish() { value = target; velocity = 0 }
}
