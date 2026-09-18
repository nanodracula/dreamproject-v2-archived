import SwiftUI

/// The lookup drawer's content for one chip: the in-context meaning as the
/// title, the usage note, the word with its speaker, the base form, tags,
/// and the list of meanings. UIKit owns the frame and motion.
struct WordLookupSheet: View {
    let chunk: FeedChunk
    let context: FeedContext
    let pronunciation: Pronunciation
    let onDismiss: () -> Void
    let onHeaderHeightChange: (CGFloat) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var wordKey = Pronunciation.Key()
    @State private var baseFormKey = Pronunciation.Key()

    var body: some View {
        VStack(spacing: 0) {
            headerZone
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeaderHeightChange($0) }
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                Rectangle().fill(.thickMaterial)
                FeedColors.sheetSurface
            }
            .ignoresSafeArea()
        }
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .strokeBorder(FeedColors.controlBorder, lineWidth: 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onDisappear {
            pronunciation.stop(wordKey)
            pronunciation.stop(baseFormKey)
        }
    }

    // MARK: - Header

    private var headerZone: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(FeedColors.sheetHandle)
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 20))
                    .foregroundStyle(FeedColors.chipSelectedBorder)
                    .padding(.top, 4)
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .lineHeight(28, for: .systemFont(ofSize: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, 38)
            .padding(.bottom, 8)
            divider
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(FeedColors.sheetControl, in: .circle)
            }
            .buttonStyle(.pressedOpacity)
            .padding(.top, 13)
            .padding(.trailing, 16)
            .accessibilityLabel(Text("close", tableName: "Feed"))
        }
    }

    /// The in-context meaning, else the first alternative, else the word,
    /// with its first character upper-cased.
    private var title: String {
        let text = chunk.meanings.first ?? chunk.text
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let details = chunk.details, !details.isEmpty {
                Text(details)
                    .font(.system(size: 16, weight: .light))
                    .lineHeight(22, for: .systemFont(ofSize: 16, weight: .light))
                    .foregroundStyle(.white)
                divider
            }

            HStack(spacing: 16) {
                speaker(size: 48, key: wordKey) { speed in
                    chunk.speechRequest(in: context, speed: speed)
                }
                Text(chunk.original)
                    .font(context.language.contentFont(size: 34, weight: .bold))
                    .lineHeight(44, for: context.language.contentUIFont(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }

            if let baseForm = chunk.baseForm, baseForm != chunk.original {
                HStack(spacing: 8) {
                    speaker(size: 32, key: baseFormKey) { speed in
                        chunk.baseFormRequest(in: context, speed: speed)
                    }
                    Text("\(Text("baseForm", tableName: "Feed"))\(Text(baseForm).font(context.language.contentFont(size: 15)))")
                        .font(.system(size: 15))
                        .lineHeight(20, for: .systemFont(ofSize: 15))
                        .foregroundStyle(FeedColors.textSecondary)
                }
                divider
            }

            tags

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(chunk.meanings.enumerated()), id: \.offset) { index, meaning in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 17))
                            .lineHeight(26, for: .systemFont(ofSize: 17))
                            .foregroundStyle(FeedColors.textSecondary)
                        Text(meaning)
                            .font(.system(size: 19))
                            .lineHeight(26, for: .systemFont(ofSize: 19))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            divider
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tags: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            // JLPT level is not in the data yet; the old app showed N-3 per design.
            Tag(text: "N-3", color: FeedColors.tagBlue)
            Tag(text: chunk.partOfSpeech.rawValue.lowercased(), color: FeedColors.tagBlue)
            if let rank = chunk.frequencyRank {
                Tag(text: "TOP-\(rank.rawValue)", color: FeedColors.tagRed)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(FeedColors.divider)
            .frame(height: 1 / displayScale)
    }

    private func speaker(
        size: CGFloat, key: Pronunciation.Key,
        request: @escaping (Pronunciation.Speed) -> Pronunciation.Request?
    ) -> some View {
        SpeakerButton(pronunciation: pronunciation, key: key, onPlay: { speed in
            guard let request = request(speed) else { return }
            Task { try? await pronunciation.play(request, for: key) }
        }) { phase, speed in
            SpeakerGlyph(size: size * 0.42, activeSize: size * 0.5, phase: phase, speed: speed)
                .frame(width: size, height: size)
                .background(FeedColors.speakerFill, in: .circle)
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineHeight(18, for: .systemFont(ofSize: 14))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 1) }
    }
}
