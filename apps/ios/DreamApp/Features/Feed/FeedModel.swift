import Foundation
import Observation

/// Presentation state of the feed: the loaded cards, which one is active,
/// the favorites overlaid from the database, the open lookup, and the
/// playback sequence for the active card.
///
/// Pages are appended and never trimmed: the collection view reuses cells, so
/// a few hundred small values cost nothing. A language change starts a new
/// run; serials keep counting so the list never confuses old and new rows.
@MainActor @Observable
final class FeedModel {
    enum Status: Equatable {
        case loading
        case ready
        case failed
    }

    /// The chip whose lookup drawer is open, and where it was on the card.
    struct Lookup: Identifiable {
        let id = UUID()
        let entryID: Int
        let chunk: FeedChunk
        /// Bottom of the chip row in the card's coordinate space.
        let rowBottom: CGFloat
    }

    /// Cards left after the active one before the next page is requested.
    static let loadAhead = 5
    static let pronounceDelay: Duration = .milliseconds(200)
    static let translationDelay: Duration = .milliseconds(100)
    static let advanceDelay: Duration = .seconds(1)

    private(set) var context: FeedContext?
    private(set) var entries: [FeedEntry] = []
    private(set) var status: Status = .loading
    private(set) var favorites: Set<FeedCard.ID> = []
    /// Index into `entries` of the card on screen; `nil` before the first
    /// card settles.
    private(set) var activeIndex: Int?
    /// Reads each card aloud as it arrives. Session-only, like hands-free:
    /// both switch off when the feed leaves the screen.
    private(set) var isAutoplaying = false
    /// Hands-free mode: read each card, then move on.
    private(set) var isAutoAdvancing = false
    private(set) var lookup: Lookup?
    /// The last failed favorite write. Cleared when its alert is dismissed.
    var saveError: String?

    /// Asks the screen to show the card at an index.
    @ObservationIgnored var onAdvance: ((Int) -> Void)?

    @ObservationIgnored private let repository: FeedRepository
    @ObservationIgnored private let settings: AppSettingsModel
    @ObservationIgnored private let pronunciation: Pronunciation
    @ObservationIgnored private var plan: FeedPagePlan?
    @ObservationIgnored private var nextSerial = 0
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var favoritesObservation: Task<Void, Never>?

    init(repository: FeedRepository, settings: AppSettingsModel, pronunciation: Pronunciation) {
        self.repository = repository
        self.settings = settings
        self.pronunciation = pronunciation
    }

    isolated deinit {
        loading?.cancel()
        playback?.cancel()
        favoritesObservation?.cancel()
    }

    var activeEntry: FeedEntry? {
        activeIndex.flatMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    func entry(id: Int) -> FeedEntry? {
        guard let first = entries.first?.id else { return nil }
        let index = id - first
        return entries.indices.contains(index) ? entries[index] : nil
    }

    // MARK: - Settings

    /// Adopts the current language settings. A new language pair starts the
    /// feed over; a changed writing display mode only redraws the chips.
    func syncSettings() {
        guard let language = settings.activeLanguage, let native = settings.nativeLanguage else { return }
        let mode = settings.enrollment(for: language.code)?.writingDisplayMode ?? .standardOnly
        let updated = FeedContext(language: language, native: native, writingLayers: language.normalized(mode).layers)
        guard updated != context else { return }
        let restarts = context?.language != updated.language || context?.native != updated.native
        context = updated
        if restarts { restart() }
    }

    private func restart() {
        run += 1
        interrupt()
        lookup = nil
        loading?.cancel()
        loading = nil
        plan = nil
        entries = []
        activeIndex = nil
        status = .loading
        if let context {
            observeFavorites(lang: context.language.code)
        }
        loadMore()
    }

    // MARK: - Loading

    /// Appends the next page. One request runs at a time; a page that fails
    /// mid-feed is retried by the next request, and only an empty feed shows
    /// the failure.
    func loadMore() {
        guard loading == nil, let context else { return }
        let run = run
        loading = Task {
            defer { if self.run == run { loading = nil } }
            do {
                if plan == nil {
                    let ids = try await repository.cardIDs(lang: context.language.code)
                    guard !Task.isCancelled, self.run == run else { return }
                    plan = FeedPagePlan(wordIDs: ids.words, sentenceIDs: ids.sentences)
                }
                guard var plan else { return }
                let draw = plan.next()
                self.plan = plan
                let records = draw.isEmpty ? FeedPageRecords(words: [], sentences: [])
                    : try await repository.fetchPage(draw)
                guard !Task.isCancelled, self.run == run else { return }
                append(records, draw: draw, context: context)
                status = .ready
            } catch {
                guard !Task.isCancelled, self.run == run else { return }
                if entries.isEmpty { status = .failed }
            }
        }
    }

    func retry() {
        guard status == .failed else { return }
        status = .loading
        loadMore()
    }

    /// Builds the page in draw order, then shuffles it so words and sentences
    /// interleave, and stamps each card with a fresh serial.
    private func append(_ records: FeedPageRecords, draw: FeedPageDraw, context: FeedContext) {
        let words = Dictionary(records.words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sentences = Dictionary(records.sentences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cards = draw.wordIDs.compactMap { words[$0] }.map { FeedCard(word: $0, language: context.language) }
        cards += draw.sentenceIDs.compactMap { sentences[$0] }.map { FeedCard(sentence: $0) }
        cards.shuffle()
        let wasEmpty = entries.isEmpty
        for card in cards {
            entries.append(FeedEntry(id: nextSerial, card: card))
            nextSerial += 1
        }
        if wasEmpty, !entries.isEmpty {
            cardBecameActive(0)
        }
    }

    private func observeFavorites(lang: String) {
        favoritesObservation?.cancel()
        favorites = []
        favoritesObservation = Task { [repository, weak self] in
            do {
                for try await favorites in repository.observeFavorites(lang: lang) {
                    guard !Task.isCancelled else { return }
                    self?.favorites = favorites
                }
            } catch {
                // The next restart observes again; loaded favorites stay as they were.
            }
        }
    }

    // MARK: - Position

    /// The card at `index` settled on screen. Requests the next page when the
    /// end is near and starts its playback sequence.
    func cardBecameActive(_ index: Int) {
        guard entries.indices.contains(index), index != activeIndex else { return }
        activeIndex = index
        if entries.count - 1 - index <= Self.loadAhead {
            loadMore()
        }
        startSequence()
    }

    /// The screen appeared or went away. Playback belongs to a visible feed,
    /// and leaving it switches autoplay and hands-free off.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            startSequence()
        } else {
            interrupt()
            isAutoplaying = false
            isAutoAdvancing = false
        }
    }

    // MARK: - Favorites

    func toggleFavorite(_ card: FeedCard) {
        let isFavorite = !favorites.contains(card.id)
        Task {
            do {
                try await repository.setFavorite(card.id, isFavorite)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    // MARK: - Lookup

    func openLookup(_ chunk: FeedChunk, in entry: FeedEntry, rowBottom: CGFloat) {
        interrupt()
        lookup = Lookup(entryID: entry.id, chunk: chunk, rowBottom: rowBottom)
    }

    func closeLookup(_ id: UUID) {
        guard lookup?.id == id else { return }
        lookup = nil
    }

    // MARK: - Playback

    /// Stops whatever the feed is playing and drops a pending advance.
    func interrupt() {
        playback?.cancel()
        playback = nil
        if let entry = activeEntry {
            pronunciation.stop(entry.titleKey)
            pronunciation.stop(entry.translationKey)
        }
    }

    /// The rail's speaker: plays the card's title, replacing the sequence.
    func listen(_ entry: FeedEntry, speed: Pronunciation.Speed) {
        guard let context else { return }
        interrupt()
        playback = Task {
            try? await pronunciation.play(entry.card.titleRequest(in: context, speed: speed), for: entry.titleKey)
        }
    }

    func toggleAutoAdvance() {
        isAutoAdvancing.toggle()
        if isAutoAdvancing {
            startSequence()
        } else {
            interrupt()
        }
    }

    /// Muting stops the current sound; unmuting reads the active card.
    func toggleAutoplay() {
        isAutoplaying.toggle()
        if isAutoplaying {
            startSequence()
        } else {
            interrupt()
        }
    }

    /// Reads the active card: title, then translation, then, hands-free, the
    /// next card. Any interruption ends the sequence where it is.
    private func startSequence() {
        playback?.cancel()
        playback = nil
        guard isVisible, let context, let entry = activeEntry, let index = activeIndex else { return }
        guard isAutoplaying || isAutoAdvancing else { return }
        playback = Task { [pronunciation] in
            do {
                try await Task.sleep(for: Self.pronounceDelay)
                try await pronunciation.play(entry.card.titleRequest(in: context), for: entry.titleKey)
                try await Task.sleep(for: Self.translationDelay)
                try await pronunciation.play(entry.card.translationRequest(in: context), for: entry.translationKey)
                guard isAutoAdvancing else { return }
                try await Task.sleep(for: Self.advanceDelay)
                // An open lookup holds the card; the next swipe resumes the rhythm.
                guard lookup == nil, activeIndex == index, !Task.isCancelled else { return }
                onAdvance?(index + 1)
            } catch {
                // Cancelled, replaced, or nothing to play.
            }
        }
    }
}
