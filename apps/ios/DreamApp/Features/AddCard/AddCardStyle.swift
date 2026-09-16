import SwiftUI

/// The Add card palette from `docs/design.md`. Kept out of `AppColors` while
/// the flow's design is still settling, as the old app did.
enum AddCardColors {
    static let background = Color(hex: 0x111318)
    static let primary = Color(hex: 0x4A6BD1)
    static let primaryRing = Color(hex: 0x4A6BD1, opacity: 0.28)
    static let primaryBorder = Color(hex: 0x4A6BD1, opacity: 0.55)

    // Translate screen
    static let surface = Color(hex: 0x1A1F27)
    static let surfaceBorder = Color(hex: 0xFFFFFF, opacity: 0.08)
    static let inputBackground = Color(hex: 0x0F141C)
    static let textSecondary = Color(hex: 0x8E949E)

    // Phrasing picker
    static let optionSurface = Color(hex: 0x22262E)
    static let optionSurfacePressed = Color(hex: 0x30353E)
    static let optionBorder = Color(hex: 0xFFFFFF, opacity: 0.07)
    static let optionDivider = Color(hex: 0xFFFFFF, opacity: 0.12)
    static let optionTextSecondary = Color(hex: 0x9AA0A8)
    static let radioIdle = Color(hex: 0x8E949E)
    static let star = Color(hex: 0xF5C542)

    static func tone(_ tone: CardTitleTone) -> Color {
        switch tone {
        case .formal: Color(hex: 0x7EE787)
        case .polite: Color(hex: 0x79C0FF)
        case .casual: Color(hex: 0xF0883E)
        case .slang: Color(hex: 0xC084FC)
        }
    }
}

/// Dims the label while pressed, the way the old app's `pressed` styles did.
struct PressedOpacityButtonStyle: ButtonStyle {
    var opacity = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? opacity : 1)
    }
}

extension ButtonStyle where Self == PressedOpacityButtonStyle {
    static var pressedOpacity: PressedOpacityButtonStyle { PressedOpacityButtonStyle() }

    static func pressedOpacity(_ opacity: Double) -> PressedOpacityButtonStyle {
        PressedOpacityButtonStyle(opacity: opacity)
    }
}
