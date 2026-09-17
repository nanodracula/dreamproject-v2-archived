import SwiftUI

/// The phrasing picker: a fixed header over scrolling option cards, sized to
/// its content up to most of the screen. Selection is local; the chosen
/// variant leaves through `onConfirm`. Pronunciation belongs to this sheet
/// through one key and stops when the sheet goes.
struct TranslationOptionsSheet: View {
    let session: TitlePickerSession
    let pronunciation: Pronunciation
    let onConfirm: (CardTitleVariant) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var selectedIndex: Int
    @State private var pronunciationKey = Pronunciation.Key()
    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    @ScaledMetric private var titleSize = 17.0

    init(
        session: TitlePickerSession,
        pronunciation: Pronunciation,
        onConfirm: @escaping (CardTitleVariant) -> Void
    ) {
        self.session = session
        self.pronunciation = pronunciation
        self.onConfirm = onConfirm
        _selectedIndex = State(initialValue: session.variants.firstIndex { $0.recommended } ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(session.variants.indices, id: \.self) { index in
                        OptionCard(
                            variant: session.variants[index],
                            language: session.learningLanguage,
                            isSelected: index == selectedIndex,
                            hairline: 1 / displayScale,
                            onSelect: { selectedIndex = index },
                            onPronounce: { pronounce(session.variants[index]) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
        }
        .presentationBackground(AddCardColors.background)
        .presentationDragIndicator(.visible)
        .presentationDetents([detent])
        .sensoryFeedback(.impact(weight: .light), trigger: selectedIndex)
        .onDisappear { pronunciation.stop(pronunciationKey) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderButton(symbol: "xmark", weight: .regular, tint: AddCardColors.optionSurface) {
                pronunciation.stop(pronunciationKey)
                dismiss()
            }
            .accessibilityLabel(Text("pickerClose", tableName: "AddCard"))

            Text("pickerTitle", tableName: "AddCard")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            HeaderButton(symbol: "checkmark", weight: .semibold, tint: AddCardColors.primary) {
                pronunciation.stop(pronunciationKey)
                onConfirm(session.variants[selectedIndex])
                dismiss()
            }
            .accessibilityLabel(Text("pickerConfirm", tableName: "AddCard"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AddCardColors.optionBorder)
                .frame(height: 1 / displayScale)
        }
    }

    /// Measure our own content; UIKit constrains the detent to the available
    /// presentation space and adds the bottom safe area.
    private var detent: PresentationDetent {
        guard headerHeight > 0, listHeight > 0 else { return .medium }
        return .height(headerHeight + listHeight)
    }

    /// Suggestions have no recording yet, so device speech reads the title
    /// in the language that produced it.
    private func pronounce(_ variant: CardTitleVariant) {
        let request = Pronunciation.Request(text: variant.title, voice: session.learningLanguage.deviceSpeech)
        Task { try? await pronunciation.play(request, for: pronunciationKey) }
    }
}

/// A 44-point glass circle with a glyph.
private struct HeaderButton: View {
    let symbol: String
    let weight: Font.Weight
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: weight))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(tint), in: .circle)
        }
        .buttonStyle(.pressedOpacity(0.65))
    }
}

/// One phrasing. A selection button fills the background, while the speaker
/// is a separate foreground control. Text passes taps through to selection.
private struct OptionCard: View {
    let variant: CardTitleVariant
    let language: LearningLanguage
    let isSelected: Bool
    let hairline: CGFloat
    let onSelect: () -> Void
    let onPronounce: () -> Void
    // Design point sizes at the standard text size, following Dynamic Type.
    @ScaledMetric private var toneSize = 14.0
    @ScaledMetric private var titleSize = 20.0
    @ScaledMetric private var translationSize = 14.0
    @ScaledMetric private var noteSize = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(toneTitle)
                    .font(.system(size: toneSize, weight: .semibold))
                    .foregroundStyle(AddCardColors.tone(variant.tone))
                if variant.recommended {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AddCardColors.star)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? AddCardColors.primary : AddCardColors.radioIdle)
            }
            .allowsHitTesting(false)

            HStack(spacing: 10) {
                speaker
                Text(variant.title)
                    .font(language.contentFont(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
            .padding(.top, 6)

            Text(variant.translation)
                .font(.system(size: translationSize))
                .foregroundStyle(AddCardColors.optionTextSecondary)
                .padding(.top, 8)
                .allowsHitTesting(false)

            Rectangle()
                .fill(AddCardColors.optionDivider)
                .frame(height: hairline)
                .padding(.vertical, 10)
                .allowsHitTesting(false)

            Text(variant.info.desc)
                .font(.system(size: noteSize, weight: .light))
                .foregroundStyle(AddCardColors.optionTextSecondary)
                .allowsHitTesting(false)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
        .background { selectionButton }
    }

    private var selectionButton: some View {
        Button {
            guard !isSelected else { return }
            onSelect()
        } label: {
            Color.clear
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(OptionCardButtonStyle(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(toneTitle), \(variant.title), \(variant.translation)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text("pronounce", tableName: "AddCard"), onPronounce)
    }

    /// The glyph is 18 by 26 in the layout; the hit area is 44 square.
    private var speaker: some View {
        Button(action: onPronounce) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 18))
                .foregroundStyle(AddCardColors.optionTextSecondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.pressedOpacity(0.65))
        .padding(.horizontal, -13)
        .padding(.vertical, -9)
        .accessibilityHidden(true)
    }

    private var toneTitle: String {
        switch variant.tone {
        case .formal: String(localized: "tone.formal", table: "AddCard")
        case .polite: String(localized: "tone.polite", table: "AddCard")
        case .casual: String(localized: "tone.casual", table: "AddCard")
        case .slang: String(localized: "tone.slang", table: "AddCard")
        }
    }
}

private struct OptionCardButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? AddCardColors.optionSurfacePressed : AddCardColors.optionSurface,
                in: .rect(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? AddCardColors.primary : AddCardColors.optionBorder, lineWidth: 1)
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Four options") {
    SheetPreview(session: .preview(variants: .previewFour))
}

#Preview("One option") {
    SheetPreview(session: .preview(variants: Array([CardTitleVariant].previewFour.prefix(1))))
}

#Preview("Long content") {
    SheetPreview(session: .preview(variants: .previewLong))
}

#Preview("Traditional Chinese") {
    SheetPreview(session: .preview(language: .mandarinTraditional, variants: .previewChinese))
}

#Preview("Large text") {
    SheetPreview(session: .preview(variants: .previewFour))
        .environment(\.dynamicTypeSize, .accessibility2)
}

private struct SheetPreview: View {
    let session: TitlePickerSession
    @State private var presented: TitlePickerSession?

    var body: some View {
        Button("Present") { presented = session }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AddCardColors.background)
            .onAppear { presented = session }
            .sheet(item: $presented) { session in
                TranslationOptionsSheet(session: session, pronunciation: .preview()) { variant in
                    print("[add-card] chosen title", variant.title)
                }
            }
    }
}
#endif
