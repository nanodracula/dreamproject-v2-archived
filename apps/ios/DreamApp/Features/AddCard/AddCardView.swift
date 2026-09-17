import SwiftUI

/// The Add card screen: a sentence in the learner's language in, native
/// phrasings out. Owns the feature model; the picker sheet and the request
/// task hang off its state, so leaving the tab winds both down through
/// ordinary view lifecycle.
struct AddCardView: View {
    private let pronunciation: Pronunciation
    @State private var model: AddCardModel
    @FocusState private var isInputFocused: Bool
    // Design point sizes at the standard text size, following Dynamic Type.
    @ScaledMetric private var titleSize = 17.0
    @ScaledMetric private var inputSize = 18.0

    /// `draft` pre-fills the input; previews use it.
    init(
        settings: AppSettingsModel,
        generation: any CardTitleGenerating,
        pronunciation: Pronunciation,
        draft: String = "",
        onSelection: @escaping (AddCardSelection) -> Void
    ) {
        self.pronunciation = pronunciation
        let model = AddCardModel(
            settings: settings,
            generation: generation,
            onSelection: onSelection
        )
        model.inputText = draft
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    input
                    actions
                    createButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AddCardColors.background)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task(id: model.pendingSubmission) {
            guard let submission = model.pendingSubmission else { return }
            await model.generate(submission)
        }
        // Fires on a root tab switch too: the container forwards UIKit
        // appearance callbacks, verified under its custom transition.
        .onDisappear {
            isInputFocused = false
            model.cancelPendingSubmission()
        }
        .background {
            TranslationOptionsDrawer(
                session: $model.pickerSession,
                pronunciation: pronunciation
            ) { session, variant in
                model.confirm(variant, in: session)
            }
        }
        .alert(
            Text("errorTitle", tableName: "AddCard"),
            isPresented: isAlertPresented,
            presenting: model.alert
        ) { _ in
        } message: { alert in
            Text(alert.message)
        }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        )
    }

    // MARK: - Header

    /// Native navigation bar title metrics, drawn by hand so the screen's
    /// own background runs under it.
    private var header: some View {
        Text("title", tableName: "AddCard")
            .font(.system(size: titleSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Input

    private var input: some View {
        TextField(
            text: $model.inputText,
            prompt: Text("inputPlaceholder", tableName: "AddCard")
                .foregroundStyle(AddCardColors.textSecondary),
            axis: .vertical
        ) {
            Text("inputLabel", tableName: "AddCard")
        }
        .font(.system(size: inputSize, weight: .medium))
        .lineSpacing(4)
        .lineLimit(4...)
        .foregroundStyle(.white)
        .tint(AddCardColors.primary)
        .focused($isInputFocused)
        .padding(16)
        // Four lines plus padding. The whole box focuses, not just the text.
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .top)
        .background(AddCardColors.inputBackground, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AddCardColors.primaryBorder, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { isInputFocused = true }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 0) {
            Spacer()
            SideAction(symbol: "camera.fill", title: "camera")
            Spacer()
            DictateButton()
            Spacer()
            SideAction(symbol: "doc.on.clipboard", title: "paste")
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private var createButton: some View {
        Button {
            isInputFocused = false
            model.submit()
        } label: {
            Group {
                if model.isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("create", tableName: "AddCard")
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AddCardColors.primary, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.pressedOpacity)
        .disabled(!model.canCreate)
        .opacity(model.canCreate ? 1 : 0.7)
        .accessibilityLabel(Text("create", tableName: "AddCard"))
    }
}

extension AddCardAlert {
    var message: LocalizedStringResource {
        switch self {
        case .inputTooLong:
            LocalizedStringResource(
                "error.input_too_long",
                defaultValue: "The text is limited to \(AddCardModel.inputLimit) characters.",
                table: "AddCard"
            )
        case .generationFailed(let error):
            error.message
        }
    }
}

extension CardTitleGenerationError {
    /// The alert copy recorded in `docs/design.md`.
    var message: LocalizedStringResource {
        switch self {
        case .invalidRequest: LocalizedStringResource("error.invalid_request", table: "AddCard")
        case .serverMisconfigured: LocalizedStringResource("error.server_misconfigured", table: "AddCard")
        case .invalidModelOutput: LocalizedStringResource("error.invalid_model_output", table: "AddCard")
        case .providerFailed: LocalizedStringResource("error.provider_failed", table: "AddCard")
        case .invalidResponse: LocalizedStringResource("error.invalid_response", table: "AddCard")
        case .unauthorized: LocalizedStringResource("error.unauthorized", table: "AddCard")
        case .notFound: LocalizedStringResource("error.not_found", table: "AddCard")
        case .rateLimited: LocalizedStringResource("error.rate_limited", table: "AddCard")
        case .timeout: LocalizedStringResource("error.timeout", table: "AddCard")
        case .serverFailed: LocalizedStringResource("error.server_failed", table: "AddCard")
        case .networkFailed: LocalizedStringResource("error.network_failed", table: "AddCard")
        }
    }
}

/// Camera and Paste: a circular button with its label beneath. No handlers
/// yet, as in the old app.
private struct SideAction: View {
    let symbol: String
    let title: LocalizedStringKey
    @ScaledMetric private var labelSize = 14.0

    var body: some View {
        VStack(spacing: 8) {
            Button {
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(AddCardColors.surface, in: .circle)
                    .overlay {
                        Circle().strokeBorder(AddCardColors.surfaceBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.pressedOpacity)
            .accessibilityLabel(Text(title, tableName: "AddCard"))

            Text(title, tableName: "AddCard")
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(AddCardColors.textSecondary)
        }
    }
}

private struct DictateButton: View {
    var body: some View {
        Button {
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(AddCardColors.primary, in: .circle)
        }
        .buttonStyle(.pressedOpacity)
        .frame(width: 104, height: 104)
        .overlay {
            Circle().strokeBorder(AddCardColors.primaryRing, lineWidth: 2)
        }
        .accessibilityLabel(Text("dictate", tableName: "AddCard"))
    }
}

// MARK: - Previews

#if DEBUG
private let previewInput = "I'd like to try this one, please."

#Preview("Empty") {
    AddCardPreview(generation: PreviewTitleGeneration(.variants(.previewFour)))
}

#Preview("Populated") {
    AddCardPreview(input: previewInput, generation: PreviewTitleGeneration(.variants(.previewFour)))
}

#Preview("Loading") {
    AddCardPreview(input: previewInput, generation: PreviewTitleGeneration(.never))
}

#Preview("Failure") {
    AddCardPreview(input: previewInput, generation: PreviewTitleGeneration(.failure(.networkFailed)))
}

#Preview("Large text") {
    AddCardPreview(input: previewInput, generation: PreviewTitleGeneration(.variants(.previewFour)))
        .environment(\.dynamicTypeSize, .accessibility2)
}

/// Owns in-memory dependencies, as the app root does, and hosts the screen
/// inside the root's navigation container.
private struct AddCardPreview: View {
    var input = ""
    let generation: any CardTitleGenerating
    @State private var preview = PreviewSupport()
    @State private var pronunciation = Pronunciation.preview()

    var body: some View {
        NavigationStack {
            AddCardView(
                settings: preview.session.settings,
                generation: generation,
                pronunciation: pronunciation,
                draft: input
            ) { selection in
                print("[add-card] chosen title", selection.variant.title)
            }
        }
        .environment(preview.session.settings)
        .task { try? await preview.session.start() }
        .onDisappear { preview.session.stop() }
    }
}
#endif
