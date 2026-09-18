import Foundation
import GRDB

nonisolated struct FeedCardIDs: Sendable {
    var words: [UUID]
    var sentences: [UUID]
}

nonisolated struct FeedPageRecords: Sendable {
    var words: [Word]
    var sentences: [Sentence]
}

/// Feed queries over the content tables.
nonisolated struct FeedRepository: Sendable {
    let writer: any DatabaseWriter

    /// Every live card id in a language, for building the decks.
    func cardIDs(lang: String) async throws -> FeedCardIDs {
        try await writer.read { db in
            FeedCardIDs(
                words: try Word.active(lang: lang).select(Word.Columns.id, as: UUID.self).fetchAll(db),
                sentences: try Sentence.active(lang: lang).select(Sentence.Columns.id, as: UUID.self).fetchAll(db)
            )
        }
    }

    /// The rows of one page. Rows removed since the decks were built are
    /// simply absent.
    func fetchPage(_ draw: FeedPageDraw) async throws -> FeedPageRecords {
        try await writer.read { db in
            FeedPageRecords(
                words: try Word.filter(keys: draw.wordIDs).filter(Word.Columns.deletedAt == nil).fetchAll(db),
                sentences: try Sentence.filter(keys: draw.sentenceIDs).filter(Sentence.Columns.deletedAt == nil).fetchAll(db)
            )
        }
    }

    /// Emits the favorited cards of the language, then again after every
    /// change to either content table, so a favorite made anywhere in the
    /// app shows on every loaded occurrence.
    func observeFavorites(lang: String) -> AsyncValueObservation<Set<FeedCard.ID>> {
        ValueObservation
            .tracking { db in try Self.fetchFavorites(db, lang: lang) }
            .removeDuplicates()
            .values(in: writer)
    }

    func setFavorite(_ id: FeedCard.ID, _ isFavorite: Bool) async throws {
        let date: Date? = isFavorite ? Date() : nil
        try await writer.write { db in
            switch id.kind {
            case .word:
                _ = try Word.filter(key: id.rowID).updateAll(
                    db, [Word.Columns.favoritedAt.set(to: date), Word.Columns.updatedAt.set(to: Date())]
                )
            case .sentence:
                _ = try Sentence.filter(key: id.rowID).updateAll(
                    db, [Sentence.Columns.favoritedAt.set(to: date), Sentence.Columns.updatedAt.set(to: Date())]
                )
            }
        }
    }

    private static func fetchFavorites(_ db: Database, lang: String) throws -> Set<FeedCard.ID> {
        let words = try Word.active(lang: lang)
            .filter(Word.Columns.favoritedAt != nil)
            .select(Word.Columns.id, as: UUID.self)
            .fetchAll(db)
        let sentences = try Sentence.active(lang: lang)
            .filter(Sentence.Columns.favoritedAt != nil)
            .select(Sentence.Columns.id, as: UUID.self)
            .fetchAll(db)
        var favorites = Set(words.map { FeedCard.ID(kind: .word, rowID: $0) })
        favorites.formUnion(sentences.map { FeedCard.ID(kind: .sentence, rowID: $0) })
        return favorites
    }
}
