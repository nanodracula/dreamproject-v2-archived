import Foundation

/// One card of the feed: a word or a sentence, projected into what the card
/// shows and speaks. Favorite and known marks live in the database and are
/// overlaid by the model, so a card never carries state of its own.
nonisolated struct FeedCard: Equatable, Sendable {
    enum Kind: Sendable {
        case word
        case sentence
    }

    /// Identifies the row behind a card. The same row can appear more than
    /// once in the feed; `FeedEntry` tells occurrences apart.
    struct ID: Hashable, Sendable {
        let kind: Kind
        let rowID: UUID
    }

    /// The last word of a sentence and its usage note.
    struct Tip: Equatable, Sendable {
        let word: String
        let details: String
    }

    let id: ID
    let lang: String
    let chunks: [FeedChunk]
    let translation: String
    /// Words only.
    let definition: String?
    /// Sentences only.
    let tip: Tip?
    /// What the synthesizer reads for the title when there is no recording.
    let speechText: String
    let photo: PhotoAsset?
    /// Asset name shown when the card has no photo.
    let placeholderImage: String
    let audio: ContentAudio
}

/// One chip of a card: a word, or the leading punctuation of a sentence.
/// Punctuation after a word is merged into that word's chip.
nonisolated struct FeedChunk: Identifiable, Equatable, Sendable {
    let id: Int
    let original: String
    var trailingPunctuation = ""
    let partOfSpeech: PartOfSpeech
    let phonetic: String?
    let transliterated: String?
    let baseForm: String?
    let frequencyRank: FrequencyRank?
    let details: String?
    let translationInContext: String?
    let otherTranslations: [String]

    /// The chip's text: the word with its trailing punctuation.
    var text: String { original + trailingPunctuation }

    /// The in-context meaning followed by the alternatives, blanks dropped.
    var meanings: [String] {
        ([translationInContext] + otherTranslations.map(Optional.some))
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// One occurrence of a card in the feed. Serials never repeat, even across a
/// restart, so the list can tell a repeated row from an old one. The keys
/// let the rail's speaker and autoplay share one animating control.
nonisolated struct FeedEntry: Identifiable, Sendable {
    let id: Int
    let card: FeedCard
    let titleKey = Pronunciation.Key()
    let translationKey = Pronunciation.Key()
}

/// The language settings a feed run was built with.
nonisolated struct FeedContext: Equatable, Sendable {
    let language: LearningLanguage
    let native: NativeLanguage
    let writingLayers: [WritingLayer]
}

// MARK: - Building cards

nonisolated extension FeedCard {
    init(word: Word, language: LearningLanguage) {
        id = ID(kind: .word, rowID: word.id)
        lang = word.lang
        chunks = [FeedChunk(
            id: 0,
            original: word.title,
            partOfSpeech: word.partOfSpeech,
            phonetic: word.writingPhonetic,
            transliterated: word.writingTransliterated,
            baseForm: word.baseForm,
            frequencyRank: word.frequencyRank,
            details: word.definition,
            translationInContext: word.translations,
            otherTranslations: []
        )]
        translation = word.translations
        definition = word.definition
        tip = nil
        speechText = language.spokenWord(word.title, phonetic: word.writingPhonetic)
        photo = word.photo.main
        placeholderImage = FeedPlaceholderImages.random(for: word.lang)
        audio = word.audio
    }

    init(sentence: Sentence) {
        id = ID(kind: .sentence, rowID: sentence.id)
        lang = sentence.lang
        let chunks = Self.chunks(from: sentence.breakdown)
        self.chunks = chunks
        translation = sentence.translations
        definition = nil
        tip = chunks.last { $0.partOfSpeech != .punctuation }
            .flatMap { chunk in
                guard let details = chunk.details, !details.isEmpty else { return nil }
                return Tip(word: chunk.original, details: details)
            }
        // Sentences keep their standard writing: the synthesizer needs it to
        // parse the grammar.
        speechText = sentence.title
        photo = sentence.photo.main
        placeholderImage = FeedPlaceholderImages.random(for: sentence.lang)
        audio = sentence.audio
    }

    private static func chunks(from breakdown: SentenceBreakdown) -> [FeedChunk] {
        var chunks: [FeedChunk] = []
        for item in breakdown.items {
            switch item {
            case .word(let word):
                chunks.append(FeedChunk(
                    id: chunks.count,
                    original: word.originalChunk,
                    partOfSpeech: word.partOfSpeech,
                    phonetic: word.writingPhonetic,
                    transliterated: word.writingTransliterated,
                    baseForm: word.baseForm,
                    frequencyRank: word.frequencyRank,
                    details: word.details,
                    translationInContext: word.translationInContext,
                    otherTranslations: word.otherTranslations
                ))
            case .punctuation(let punctuation):
                if chunks.isEmpty {
                    chunks.append(FeedChunk(
                        id: 0,
                        original: punctuation.originalChunk,
                        partOfSpeech: .punctuation,
                        phonetic: nil,
                        transliterated: nil,
                        baseForm: nil,
                        frequencyRank: nil,
                        details: punctuation.details,
                        translationInContext: nil,
                        otherTranslations: []
                    ))
                } else {
                    chunks[chunks.count - 1].trailingPunctuation += punctuation.originalChunk
                }
            }
        }
        return chunks
    }
}

/// Bundled photos for cards without one: a Korean set, and a generic set
/// for every other language.
nonisolated enum FeedPlaceholderImages {
    static let generic = ["feed-img-placeholder", "feed-img-placeholder-2", "feed-japanese-cafe"]
    static let korean = [
        "feed-korean-hanok", "feed-korean-mountains", "feed-korean-seoul-evening",
        "feed-korean-jeju-coast", "feed-korean-palace-garden",
    ]

    static func random(for lang: String) -> String {
        (lang == "ko" ? korean : generic).randomElement()!
    }
}

// MARK: - Playback

nonisolated extension FeedCard {
    func titleRequest(in context: FeedContext, speed: Pronunciation.Speed = .normal) -> Pronunciation.Request {
        Pronunciation.Request(text: speechText, voice: context.language.deviceSpeech, recording: audio.title, speed: speed)
    }

    /// The translation recording plays only when it was made for the
    /// learner's native language; otherwise device speech reads the text.
    func translationRequest(in context: FeedContext) -> Pronunciation.Request {
        let recording = audio.translation.flatMap { $0.lang == context.native.code ? $0 : nil }
        return Pronunciation.Request(text: translation, voice: context.native.deviceSpeech, recording: recording)
    }
}

nonisolated extension FeedChunk {
    /// Device speech for the chip's word, read the way an isolated word is.
    func speechRequest(in context: FeedContext, speed: Pronunciation.Speed = .normal) -> Pronunciation.Request {
        Pronunciation.Request(
            text: context.language.spokenWord(original, phonetic: phonetic),
            voice: context.language.deviceSpeech,
            speed: speed
        )
    }

    func baseFormRequest(in context: FeedContext, speed: Pronunciation.Speed = .normal) -> Pronunciation.Request? {
        guard let baseForm, baseForm != original else { return nil }
        return Pronunciation.Request(text: baseForm, voice: context.language.deviceSpeech, speed: speed)
    }
}
