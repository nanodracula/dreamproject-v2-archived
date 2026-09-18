import Foundation

/// A shuffled, never-ending deck of ids. Draws hand out the shuffle in order
/// and reshuffle once it runs out, so every card comes around before any
/// repeats, and a small library still fills an endless feed.
nonisolated struct FeedDeck<ID: Hashable & Sendable>: Sendable {
    private let ids: [ID]
    private var remaining: [ID] = []

    init(_ ids: [ID]) {
        self.ids = ids
    }

    var isEmpty: Bool { ids.isEmpty }

    /// Up to `count` ids, never more than the deck holds and never the same
    /// id twice in one draw.
    mutating func draw(_ count: Int) -> [ID] {
        let target = min(count, ids.count)
        var drawn: [ID] = []
        drawn.reserveCapacity(target)
        while drawn.count < target {
            if remaining.isEmpty { remaining = ids.shuffled() }
            let id = remaining.removeLast()
            if !drawn.contains(id) { drawn.append(id) }
        }
        return drawn
    }
}

/// What one page of the feed should fetch.
nonisolated struct FeedPageDraw: Sendable {
    let wordIDs: [UUID]
    let sentenceIDs: [UUID]

    var isEmpty: Bool { wordIDs.isEmpty && sentenceIDs.isEmpty }
}

/// Composes pages from a word deck and a sentence deck: about two single
/// words per page of twenty, and more words when sentences run short.
nonisolated struct FeedPagePlan: Sendable {
    static let pageSize = 20
    static let wordsPerPage = 2

    private var words: FeedDeck<UUID>
    private var sentences: FeedDeck<UUID>

    init(wordIDs: [UUID], sentenceIDs: [UUID]) {
        words = FeedDeck(wordIDs)
        sentences = FeedDeck(sentenceIDs)
    }

    var isEmpty: Bool { words.isEmpty && sentences.isEmpty }

    mutating func next() -> FeedPageDraw {
        let sentenceIDs = sentences.draw(Self.pageSize - Self.wordsPerPage)
        let wordIDs = words.draw(Self.pageSize - sentenceIDs.count)
        return FeedPageDraw(wordIDs: wordIDs, sentenceIDs: sentenceIDs)
    }
}
