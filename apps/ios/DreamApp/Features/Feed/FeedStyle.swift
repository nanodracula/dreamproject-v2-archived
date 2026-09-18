import SwiftUI

/// The feed palette from `docs/design.md`. Kept out of `AppColors`, as the
/// old app did, because it is meant to become dynamic, derived from the card
/// image, later.
enum FeedColors {
    static let background = Color(hex: 0x111318)
    static let surface = Color(hex: 0x1E2949)
    static let accent = Color(hex: 0x62B0FF)
    static let accentSoft = Color(hex: 0x173B5C)
    static let textSecondary = Color.white.opacity(0.85)
    static let textMuted = Color.white.opacity(0.76)
    static let railIcon = Color.white.opacity(0.08)
    static let heroControl = Color(red: 10 / 255, green: 14 / 255, blue: 20 / 255).opacity(0.55)
    static let chipSelectedBorder = Color(hex: 0xE8C158)
    static let controlBorder = Color.white.opacity(0.12)

    // Word lookup
    static let tagBlue = Color(hex: 0x5B7CFA)
    static let tagRed = Color(hex: 0xE0645A)
    static let divider = Color.white.opacity(0.18)
    static let sheetSurface = Color(red: 36 / 255, green: 41 / 255, blue: 53 / 255).opacity(0.7)
    static let sheetHandle = Color.white.opacity(0.22)
    static let sheetControl = Color.white.opacity(0.12)
    static let speakerFill = Color.white.opacity(0.08)
}

enum FeedMetrics {
    static let heroHeight: CGFloat = 380
    /// Room above the chips for the hero fade to ease in.
    static let heroFadeLead: CGFloat = 120
    static let lookupTopGap: CGFloat = 10
    /// The right padding that keeps body text clear of the action rail.
    static let railClearance: CGFloat = 64
}

/// A chip's tinted fill and its softer outline of the same hue, so the same
/// part of speech is always the same color across cards.
struct ChipPalette {
    let fill: Color
    let border: Color
}

extension FeedColors {
    static func chip(for partOfSpeech: PartOfSpeech) -> ChipPalette {
        switch partOfSpeech {
        case .noun, .properNoun, .pronoun, .numeral:
            ChipPalette(fill: Color(red: 41 / 255, green: 70 / 255, blue: 127 / 255).opacity(0.92),
                        border: Color(red: 122 / 255, green: 156 / 255, blue: 224 / 255).opacity(0.5))
        case .verb, .auxiliary:
            ChipPalette(fill: Color(red: 84 / 255, green: 103 / 255, blue: 43 / 255).opacity(0.92),
                        border: Color(red: 170 / 255, green: 184 / 255, blue: 110 / 255).opacity(0.5))
        case .adjective, .adverb, .determiner:
            ChipPalette(fill: Color(red: 69 / 255, green: 49 / 255, blue: 109 / 255).opacity(0.92),
                        border: Color(red: 160 / 255, green: 138 / 255, blue: 220 / 255).opacity(0.5))
        case .adposition, .particle, .subordinatingConjunction, .coordinatingConjunction:
            ChipPalette(fill: Color(red: 59 / 255, green: 67 / 255, blue: 75 / 255).opacity(0.92),
                        border: Color(red: 150 / 255, green: 156 / 255, blue: 166 / 255).opacity(0.5))
        case .interjection, .punctuation, .symbol, .other:
            ChipPalette(fill: Color(red: 47 / 255, green: 50 / 255, blue: 56 / 255).opacity(0.92),
                        border: Color(red: 130 / 255, green: 134 / 255, blue: 142 / 255).opacity(0.5))
        }
    }
}

/// The gradient over the bottom of the hero photo, behind the chips:
/// transparent at the top so it dissolves into the photo, near-solid at the
/// bottom so it merges into the card. A bias-warped smootherstep, as the old
/// app computed it.
enum HeroFade {
    static let peak = 0.84
    static let strength = 0.65
    static let stopCount = 4

    static let stops: [Gradient.Stop] = (0..<stopCount).map { index in
        let position = Double(index) / Double(stopCount - 1)
        return Gradient.Stop(color: .black.opacity(alpha(at: position, bias: strength) * peak), location: position)
    }

    private static func alpha(at t: Double, bias: Double) -> Double {
        let x = t / ((1 / bias - 2) * (1 - t) + 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
