import SwiftUI

/// A speaker control driven by `Pronunciation`: tap plays or stops, holding
/// plays slowly. While its key is sounding it shows a pulsing stop glyph,
/// pink at normal speed and amber when slow, as the old pronunciation icon did.
struct SpeakerButton<Label: View>: View {
    let pronunciation: Pronunciation
    let key: Pronunciation.Key
    let onPlay: (Pronunciation.Speed) -> Void
    /// Draws the control for the current phase and speed.
    @ViewBuilder let label: (Pronunciation.Phase?, Pronunciation.Speed?) -> Label
    @State private var isPressed = false

    var body: some View {
        let activity = pronunciation.activity
        let phase = activity?.key == key ? activity?.phase : nil
        let speed = activity?.key == key ? activity?.speed : nil
        label(phase, speed)
            .opacity(isPressed ? 0.7 : 1)
            .contentShape(.rect)
            .onTapGesture {
                if phase != nil {
                    pronunciation.stop(key)
                } else {
                    onPlay(.normal)
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                onPlay(.slow)
            } onPressingChanged: { pressing in
                isPressed = pressing
            }
    }
}

/// The speaker glyph in its three states.
struct SpeakerGlyph: View {
    var idleSymbol = "speaker.wave.2.fill"
    var idleColor: Color = .white
    var size: CGFloat
    var activeSize: CGFloat
    let phase: Pronunciation.Phase?
    let speed: Pronunciation.Speed?

    var body: some View {
        if phase != nil {
            Image(systemName: "stop.circle")
                .font(.system(size: activeSize))
                .foregroundStyle(speed == .slow ? Color(hex: 0xF5C542) : Color(hex: 0xFA5D7D))
                .symbolEffect(.pulse, options: .repeating, isActive: phase == .playing)
        } else {
            Image(systemName: idleSymbol)
                .font(.system(size: size))
                .foregroundStyle(idleColor)
        }
    }
}
