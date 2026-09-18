import SwiftUI

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
