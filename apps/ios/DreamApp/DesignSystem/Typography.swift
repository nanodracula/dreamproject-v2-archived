import SwiftUI
import UIKit

extension View {
    /// Gives text the absolute line box the old app's `lineHeight` set: the
    /// gap between lines and the half-leading above and below both come from
    /// the difference to the font's natural line height.
    func lineHeight(_ height: CGFloat, for font: UIFont) -> some View {
        let extra = max(0, height - font.lineHeight)
        return self
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}
