import Foundation
import Observation

/// One tap of Create. Captures the language context at submission time so a
/// settings change while the request runs cannot mislabel its results.
nonisolated struct TitleSubmission: Identifiable, Equatable, Sendable {
    let id = UUID()
    let request: CardTitleInput
    let learningLanguage: LearningLanguage
}

/// A generated batch, presented once. A new batch is a new session, so the
/// sheet's own selection state starts over with it.
nonisolated struct TitlePickerSession: Identifiable, Sendable {
    let id = UUID()
    let request: CardTitleInput
    let learningLanguage: LearningLanguage
    let variants: [CardTitleVariant]
}

/// What the flow hands on for card creation.
nonisolated struct AddCardSelection: Sendable {
    let request: CardTitleInput
    let learningLanguage: LearningLanguage
    let variant: CardTitleVariant
}

/// Why a Create tap ended without a picker.
nonisolated enum AddCardAlert: Equatable, Sendable {
    case inputTooLong
    case generationFailed(CardTitleGenerationError)
}

/// Presentation state of the Add card screen: the draft, the in-flight
/// submission, its outcome, and the confirmation hand-off. The view runs the
/// request through `.task(id:)` keyed on `pendingSubmission`, so leaving the
/// screen cancels it through ordinary view lifecycle.
@MainActor @Observable
final class AddCardModel {
    /// The longest sentence the title service accepts, in characters.
    static let inputLimit = 120

    var inputText = ""
    /// Drives the request task. Cleared when the request settles or the
    /// screen goes away, so returning never resubmits.
    private(set) var pendingSubmission: TitleSubmission?
    /// Drives the picker sheet.
    var pickerSession: TitlePickerSession?
    /// Why the last Create tap produced nothing. Cleared when its alert is
    /// dismissed.
    var alert: AddCardAlert?

    private let settings: AppSettingsModel
    private let generation: any CardTitleGenerating
    private let onSelection: (AddCardSelection) -> Void

    init(
        settings: AppSettingsModel,
        generation: any CardTitleGenerating,
        onSelection: @escaping (AddCardSelection) -> Void
    ) {
        self.settings = settings
        self.generation = generation
        self.onSelection = onSelection
    }

    var isGenerating: Bool { pendingSubmission != nil }

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The languages a request needs; `nil` until settings have loaded and
    /// resolve to supported languages with an enrollment.
    private var languageContext: (learning: LearningLanguage, native: NativeLanguage, level: KnowledgeLevel)? {
        guard let learning = settings.activeLanguage,
              let native = settings.nativeLanguage,
              let enrollment = settings.enrollment(for: learning.code)
        else { return nil }
        return (learning, native, enrollment.knowledgeLevel)
    }

    var canCreate: Bool {
        !trimmedInput.isEmpty && !isGenerating && languageContext != nil
    }

    // MARK: - Generation

    /// Captures the draft and language settings as one submission. Repeated
    /// taps while one is running are ignored; an over-long draft is refused
    /// with an alert and kept for editing.
    func submit() {
        guard canCreate, let context = languageContext else { return }
        guard trimmedInput.count <= Self.inputLimit else {
            alert = .inputTooLong
            return
        }
        let request = CardTitleInput(
            inputText: trimmedInput,
            learningLanguage: context.learning,
            nativeLanguage: context.native,
            knowledgeLevel: context.level
        )
        pendingSubmission = TitleSubmission(request: request, learningLanguage: context.learning)
    }

    /// Runs one submission to completion. Results and errors are published
    /// only when the submission is still the pending one and the task was
    /// not cancelled, so a cancelled request neither opens the picker nor
    /// shows an alert. The draft is kept on failure.
    func generate(_ submission: TitleSubmission) async {
        defer {
            // A newer submission may already be pending: only this one's
            // entry is cleared.
            if pendingSubmission?.id == submission.id {
                pendingSubmission = nil
            }
        }
        let outcome: Result<[CardTitleVariant], CardTitleGenerationError>
        do {
            outcome = .success(try await generation.generateTitles(for: submission.request))
        } catch {
            outcome = .failure(error)
        }
        guard !Task.isCancelled, pendingSubmission?.id == submission.id else { return }

        switch outcome {
        case .success(let variants) where variants.isEmpty:
            alert = .generationFailed(.invalidResponse)
        case .success(let variants):
            pickerSession = TitlePickerSession(
                request: submission.request,
                learningLanguage: submission.learningLanguage,
                variants: variants
            )
        case .failure(let error):
            alert = .generationFailed(error)
        }
    }

    /// Drops the in-flight submission. Cancellation reaches the request
    /// through the view's task; this guarantees nothing re-runs on return.
    func cancelPendingSubmission() {
        pendingSubmission = nil
    }

    // MARK: - Confirmation

    /// Hands the chosen variant on and clears the draft, matching the old
    /// flow. The sheet dismisses itself.
    func confirm(_ variant: CardTitleVariant, in session: TitlePickerSession) {
        onSelection(AddCardSelection(
            request: session.request,
            learningLanguage: session.learningLanguage,
            variant: variant
        ))
        inputText = ""
    }
}

// MARK: - Preview fixtures

#if DEBUG
/// Answers generation without the network: a fixed batch, a failure, or a
/// request that never completes, for the loading state.
nonisolated struct PreviewTitleGeneration: CardTitleGenerating {
    enum Outcome: Sendable {
        case variants([CardTitleVariant])
        case failure(CardTitleGenerationError)
        case never
    }

    let outcome: Outcome

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func generateTitles(for input: CardTitleInput) async throws(CardTitleGenerationError) -> [CardTitleVariant] {
        switch outcome {
        case .variants(let variants):
            return variants
        case .failure(let error):
            throw error
        case .never:
            while true {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    throw .networkFailed
                }
            }
        }
    }
}

nonisolated extension TitlePickerSession {
    static func preview(language: LearningLanguage = .japanese, variants: [CardTitleVariant]) -> TitlePickerSession {
        TitlePickerSession(
            request: CardTitleInput(
                inputText: "I'd like to try this one, please.",
                learningLanguage: language,
                nativeLanguage: .english,
                knowledgeLevel: .beginner
            ),
            learningLanguage: language,
            variants: variants
        )
    }
}

nonisolated extension CardTitleVariant {
    fileprivate static func preview(
        _ title: String,
        _ translation: String,
        tone: CardTitleTone,
        recommended: Bool = false,
        desc: String
    ) -> CardTitleVariant {
        CardTitleVariant(
            title: title,
            translation: translation,
            contentType: .sentence,
            sentenceType: nil,
            tone: tone,
            recommended: recommended,
            info: Info(desc: desc)
        )
    }
}

nonisolated extension [CardTitleVariant] {
    static let previewFour: [CardTitleVariant] = [
        .preview(
            "これを試してみたいです。", "I'd like to try this one.",
            tone: .polite, recommended: true,
            desc: "The neutral polite form; what a customer says in a shop."
        ),
        .preview(
            "これを試させていただけますか。", "May I try this one?",
            tone: .formal,
            desc: "Humble request form; suited to a formal store or when asking a favor."
        ),
        .preview(
            "これ、試してみたい。", "Wanna try this one.",
            tone: .casual,
            desc: "Plain form with the particle dropped; between friends."
        ),
        .preview(
            "これ、試してみよっかな。", "Guess I'll give this one a go.",
            tone: .slang,
            desc: "Muttered to oneself; relaxed and colloquial."
        ),
    ]

    static let previewLong: [CardTitleVariant] = [
        .preview(
            "お忙しいところ恐れ入りますが、こちらの商品を一度試させていただいてもよろしいでしょうか。",
            "I'm sorry to trouble you while you're busy, but would it be all right if I tried this "
                + "product once?",
            tone: .formal, recommended: true,
            desc: "A full keigo request with a softening preface. Shop staff hear this from customers who "
                + "want to be especially courteous, and it is the register a learner would use in a "
                + "department store or when the assistant has clearly gone out of their way already."
        ),
        .preview(
            "これ試したい。", "Wanna try this.",
            tone: .casual,
            desc: "Bare plain form."
        ),
    ]

    static let previewChinese: [CardTitleVariant] = [
        .preview(
            "我想試試這個。", "I'd like to try this one.",
            tone: .polite, recommended: true,
            desc: "Neutral and natural in Taiwan; the everyday way to ask in a shop."
        ),
        .preview(
            "請問我可以試一下這個嗎？", "Excuse me, may I try this one?",
            tone: .formal,
            desc: "Opens with 請問 to soften the request; suited to staff you do not know."
        ),
    ]
}
#endif
