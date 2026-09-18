import SwiftUI
import UIKit

extension LearningLanguage {
    /// The font for learning content in this language: the declared family
    /// when there is one, so CJK glyph forms follow the text rather than the
    /// device language, otherwise the system font. Interface text never
    /// uses it.
    func contentFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(contentUIFont(size: size, weight: weight))
    }

    /// The UIKit form of `contentFont`, for line metrics and UIKit labels.
    func contentUIFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        guard let contentFontFamily else {
            return .systemFont(ofSize: size, weight: weight.uiWeight)
        }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: contentFontFamily,
            .traits: [UIFontDescriptor.TraitKey.weight: weight.uiWeight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
