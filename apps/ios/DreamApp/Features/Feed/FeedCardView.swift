import SwiftUI

/// Screen metrics the cards need from their UIKit container.
@MainActor @Observable
final class FeedLayoutMetrics {
    var safeAreaInsets = EdgeInsets()
}

/// One full-screen card: the photo hero with the chips over its fade, the
/// translation body, and the action rail. Reads the model directly, so
/// favorites, the open lookup, and playback state redraw without the list's
/// involvement.
struct FeedCardView: View {
    let entry: FeedEntry
    let model: FeedModel
    let layout: FeedLayoutMetrics
    let pronunciation: Pronunciation
    let mediaCache: MediaCache
    @State private var chipRowBottom: CGFloat = 0
    /// A stub, as in the old app: not stored, and forgotten with the card.
    @State private var isKnown = false

    private nonisolated static let space = "feedCard"

    var body: some View {
        let context = model.context
        VStack(alignment: .leading, spacing: 0) {
            hero(context)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FeedColors.background)
        .overlay(alignment: .bottomTrailing) { rail }
        .coordinateSpace(.named(Self.space))
        // Full-bleed: the photo runs under the status bar and the rail
        // clears the floating bar through the container's insets.
        .ignoresSafeArea()
        // A reused cell shows a different card; its view-local state starts over.
        .id(entry.id)
    }

    // MARK: - Hero

    private func hero(_ context: FeedContext?) -> some View {
        FeedHeroImage(photo: entry.card.photo, placeholder: entry.card.placeholderImage, mediaCache: mediaCache)
            .frame(height: FeedMetrics.heroHeight)
            .overlay(alignment: .bottom) {
                chips(context)
                    .padding(.top, FeedMetrics.heroFadeLead)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(stops: HeroFade.stops, startPoint: .top, endPoint: .bottom))
            }
            .clipped()
    }

    private func chips(_ context: FeedContext?) -> some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(entry.card.chunks) { chunk in
                BreakdownChip(
                    chunk: chunk,
                    language: context?.language,
                    layers: context?.writingLayers ?? [.standard],
                    isSelected: model.lookup?.entryID == entry.id && model.lookup?.chunk.id == chunk.id
                ) {
                    model.openLookup(chunk, in: entry, rowBottom: chipRowBottom)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: { chipRowBottom = $0 }
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.card.translation)
                .font(.system(size: 18))
                .lineHeight(26, for: .systemFont(ofSize: 18))
                .foregroundStyle(FeedColors.textSecondary)
                .padding(.trailing, FeedMetrics.railClearance)
                .padding(.bottom, 16)

            if let definition = entry.card.definition {
                VStack(alignment: .leading, spacing: 4) {
                    Text("definition", tableName: "Feed")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.4)
                        .lineHeight(18, for: .systemFont(ofSize: 13, weight: .bold))
                        .foregroundStyle(FeedColors.accent)
                    Text(definition)
                        .font(.system(size: 17))
                        .lineHeight(24, for: .systemFont(ofSize: 17))
                        .foregroundStyle(.white)
                }
                .padding(.trailing, FeedMetrics.railClearance)
                .padding(.bottom, 16)
            }

            if let tip = entry.card.tip {
                tipCard(tip)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func tipCard(_ tip: FeedCard.Tip) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 20))
                .foregroundStyle(FeedColors.accent)
                .frame(width: 44, height: 44)
                .background(FeedColors.accentSoft, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("wordToNotice", tableName: "Feed")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .lineHeight(16, for: .systemFont(ofSize: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(tip.word) — \(tip.details)")
                    .font(.system(size: 14))
                    .lineHeight(20, for: .systemFont(ofSize: 14))
                    .foregroundStyle(FeedColors.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedColors.surface, in: .rect(cornerRadius: 16))
        .padding(.trailing, FeedMetrics.railClearance)
    }

    // MARK: - Rail

    private var rail: some View {
        let isFavorite = model.favorites.contains(entry.card.id)
        return VStack(spacing: 16) {
            RailButton(
                symbol: isFavorite ? "heart.fill" : "heart",
                label: nil,
                isActive: isFavorite
            ) {
                model.toggleFavorite(entry.card)
            }

            SpeakerButton(pronunciation: pronunciation, key: entry.titleKey, onPlay: { speed in
                model.listen(entry, speed: speed)
            }) { phase, speed in
                RailLabel(label: Text("listen", tableName: "Feed"), isActive: phase != nil) {
                    SpeakerGlyph(size: 22, activeSize: 24, phase: phase, speed: speed)
                }
            }

            RailButton(
                symbol: isKnown ? "checkmark.circle.fill" : "checkmark.circle",
                label: Text("known", tableName: "Feed"),
                isActive: isKnown
            ) {
                isKnown.toggle()
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, layout.safeAreaInsets.bottom + 16)
    }
}

// MARK: - Chips

/// One breakdown chip: the reading above, the tinted word in the middle, and
/// the romanization below. The selection ring is drawn outside the box so
/// selecting never changes the chip's size.
private struct BreakdownChip: View {
    let chunk: FeedChunk
    let language: LearningLanguage?
    let layers: [WritingLayer]
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let palette = FeedColors.chip(for: chunk.partOfSpeech)
        VStack(spacing: 0) {
            if layers.contains(.phonetic) {
                Text(phonetic)
                    .font(contentFont(size: 12))
                    .lineHeight(16, for: contentUIFont(size: 12))
                    .foregroundStyle(FeedColors.textMuted)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.9), radius: 4, y: 2)
                    .padding(.bottom, 2)
            }
            Text(chunk.text)
                .font(contentFont(size: 24, weight: .semibold))
                .lineHeight(32, for: contentUIFont(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(palette.fill, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(FeedColors.chipSelectedBorder, lineWidth: 3)
                            .padding(-4)
                    }
                }
            if layers.contains(.transliterated), let transliterated = chunk.transliterated, !transliterated.isEmpty {
                Text(transliterated)
                    .font(.system(size: 13))
                    .lineHeight(18, for: .systemFont(ofSize: 13))
                    .foregroundStyle(FeedColors.textMuted)
                    .shadow(color: .black.opacity(0.9), radius: 4, y: 2)
                    .padding(.top, 2)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
    }

    /// A chip with no distinct reading keeps a blank line, so the row's
    /// chips share a baseline.
    private var phonetic: String {
        guard let phonetic = chunk.phonetic, !phonetic.isEmpty, phonetic != chunk.original else { return " " }
        return phonetic
    }

    private func contentFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        language?.contentFont(size: size, weight: weight) ?? .system(size: size, weight: weight)
    }

    private func contentUIFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        language?.contentUIFont(size: size, weight: weight) ?? .systemFont(ofSize: size, weight: weight.uiWeight)
    }
}

// MARK: - Hero image

/// The card photo, downsampled off the main actor once the cache has the
/// file; the bundled placeholder when the card has no photo.
private struct FeedHeroImage: View {
    let photo: PhotoAsset?
    let placeholder: String
    let mediaCache: MediaCache
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if photo == nil {
                    Image(placeholder).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: photo?.storagePath) {
                image = await load(photo)
            }
    }

    private func load(_ photo: PhotoAsset?) async -> UIImage? {
        guard let photo, let file = try? await mediaCache.file(for: photo.storagePath) else { return nil }
        let side = 1200 * displayScale
        return await UIImage(contentsOfFile: file.path(percentEncoded: false))?
            .byPreparingThumbnail(ofSize: CGSize(width: side, height: side))
    }
}

// MARK: - Rail controls

private struct RailButton: View {
    let symbol: String
    let label: Text?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RailLabel(label: label, isActive: isActive) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? FeedColors.accent : .white)
            }
        }
        .buttonStyle(.pressedOpacity)
    }
}

/// A 48-point circle with its label beneath.
private struct RailLabel<Icon: View>: View {
    let label: Text?
    let isActive: Bool
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 4) {
            icon()
                .frame(width: 48, height: 48)
                .background(isActive ? FeedColors.accentSoft : FeedColors.railIcon, in: .circle)
            if let label {
                label
                    .font(.system(size: 12))
                    .lineHeight(16, for: .systemFont(ofSize: 12))
                    .foregroundStyle(FeedColors.textSecondary)
            }
        }
        .contentShape(.rect)
    }
}
