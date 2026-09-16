import SwiftUI

/// A floating Liquid Glass bar whose selection stretches toward its destination.
struct MainNavigationOriginal<Item: MainNavigationItem>: MainNavigationBar {
    let items: [Item]
    @Binding var selection: Item.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: PillPosition
    @State private var movingForward = false

    static var metrics: MainNavigationMetrics {
        MainNavigationMetrics(height: Layout.height, sideInset: 32)
    }

    init(items: [Item], selection: Binding<Item.ID>) {
        self.items = items
        _selection = selection
        let index = CGFloat(items.firstIndex { $0.id == selection.wrappedValue } ?? 0)
        _position = State(initialValue: PillPosition(start: index, end: index + 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = geometry.size.width / CGFloat(max(items.count, 1))

            AnimatedPillEdge(value: position.start) { start in
                AnimatedPillEdge(value: position.end) { end in
                    bar(position: PillPosition(start: start, end: end), slotWidth: slotWidth)
                }
                .animation(
                    reduceMotion ? nil : .spring(movingForward ? Motion.leadingEdge : Motion.trailingEdge),
                    value: position.end
                )
            }
            .animation(
                reduceMotion ? nil : .spring(movingForward ? Motion.trailingEdge : Motion.leadingEdge),
                value: position.start
            )
        }
        .frame(height: Layout.pillHeight)
        .padding(Layout.inset)
        .frame(height: Self.metrics.height)
        .glassEffect(.regular.interactive(!reduceMotion), in: .capsule)
        .onChange(of: selection) { _, newValue in
            let index = CGFloat(items.firstIndex { $0.id == newValue } ?? 0)
            movingForward = index > position.center
            position = PillPosition(start: index, end: index + 1)
        }
    }

    private func bar(position: PillPosition, slotWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if !reduceMotion {
                Capsule()
                    .fill(Palette.pill)
                    .frame(width: slotWidth, height: Layout.pillHeight)
                    .scaleEffect(x: max(0.01, position.end - position.start), y: 1)
                    .offset(x: position.center * slotWidth)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    slot(for: item, fill: max(0, 1 - abs(position.center - CGFloat(index))))
                }
            }
            .animation(reduceMotion ? Motion.reduced : nil, value: selection)
        }
    }

    private func slot(for item: Item, fill: CGFloat) -> some View {
        let isSelected = item.id == selection
        let glyphFill = reduceMotion ? (isSelected ? 1.0 : 0.0) : Double(fill)
        return Button {
            selection = item.id
        } label: {
            ZStack {
                symbol(item.symbol, color: Palette.inactiveGlyph)
                    .opacity(1 - glyphFill)
                symbol(item.selectedSymbol, color: Palette.activeGlyph)
                    .opacity(glyphFill)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if reduceMotion {
                    Capsule()
                        .fill(Palette.pill)
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .fontWeight(.regular)
            .foregroundStyle(color)
            .frame(width: Layout.iconSize, height: Layout.iconSize)
    }
}

/// Each edge gets its own spring and retains its presentation value when
/// retargeted. The content receives those values for both geometry and icon fill.
private struct AnimatedPillEdge<Content: View>: View, Animatable {
    var value: CGFloat
    let content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }

    var body: some View { content(value) }
}

/// Both edges are measured in slots. Icon fill uses their interpolated center,
/// so it follows the visible pill even when a new tap interrupts the springs.
private struct PillPosition {
    var start: CGFloat
    var end: CGFloat

    var center: CGFloat { (start + end) / 2 - 0.5 }
}

private enum Layout {
    static let height: CGFloat = 58
    static let inset: CGFloat = 7
    static let pillHeight = height - inset * 2
    static let iconSize: CGFloat = 23
}

private enum Palette {
    static let pill = Color.white.opacity(0.14)
    static let activeGlyph = Color(hex: 0xE9ECEF)
    static let inactiveGlyph = Color(hex: 0xB0B4BA)
}

private enum Motion {
    // Each edge settles on its own spring; there is no fixed-duration cutoff.
    static let leadingEdge = Spring(mass: 0.7, stiffness: 400, damping: 30)
    static let trailingEdge = Spring(mass: 0.9, stiffness: 240, damping: 28)
    static let reduced = Animation.easeOut(duration: 0.1)
}
