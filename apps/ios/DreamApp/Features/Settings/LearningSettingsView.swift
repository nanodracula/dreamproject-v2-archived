import SwiftUI

/// Settings of one enrolled learning language.
struct LearningSettingsView: View {
    let languageCode: String
    @Environment(AppSettingsModel.self) private var settings

    private var language: LearningLanguage? { LearningLanguage.with(code: languageCode) }

    var body: some View {
        List {
            if let language, let enrollment = settings.enrollment(for: languageCode) {
                Section {
                    Picker(selection: knowledgeLevel(of: enrollment)) {
                        Text("knowledgeLevelBeginner", tableName: "Settings").tag(KnowledgeLevel.beginner)
                        Text("knowledgeLevelIntermediate", tableName: "Settings").tag(KnowledgeLevel.intermediate)
                        Text("knowledgeLevelAdvanced", tableName: "Settings").tag(KnowledgeLevel.advanced)
                    } label: {
                        Text("knowledgeLevelLabel", tableName: "Settings")
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.canEdit)
                }

                // A language with no reading aids has nothing to choose.
                if language.availableWritingDisplayModes.count > 1 {
                    Section {
                        Picker(selection: writingDisplayMode(of: enrollment, in: language)) {
                            ForEach(language.availableWritingDisplayModes, id: \.self) { mode in
                                Text(modeLabel(mode, in: language)).tag(mode)
                            }
                        } label: {
                            Text("writingDisplayModeLabel", tableName: "Settings")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .disabled(!settings.canEdit)
                    } header: {
                        Text("writingDisplayModeLabel", tableName: "Settings")
                    } footer: {
                        Text("writingDisplayModeDescription", tableName: "Settings")
                    }
                }
            } else if settings.isLoaded {
                // Unsupported or not enrolled: no saved values to show.
                Text("learningNotEnrolled", tableName: "Settings")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsSaveErrorAlert()
    }

    private var title: String {
        String(
            format: NSLocalizedString("learningTitle", tableName: "Settings", comment: ""),
            language?.nativeName ?? languageCode
        )
    }

    // Selecting saves; the picker moves once the change is committed.

    private func knowledgeLevel(of enrollment: UserLearningLanguageSettings) -> Binding<KnowledgeLevel> {
        Binding(
            get: { enrollment.knowledgeLevel },
            set: { level in
                guard level != enrollment.knowledgeLevel else { return }
                Task { await settings.setKnowledgeLevel(level, for: languageCode) }
            }
        )
    }

    /// Shows the saved mode reduced to the language's layers; saves the
    /// chosen mode as is.
    private func writingDisplayMode(
        of enrollment: UserLearningLanguageSettings, in language: LearningLanguage
    ) -> Binding<WritingDisplayMode> {
        Binding(
            get: { language.normalized(enrollment.writingDisplayMode) },
            set: { mode in
                guard mode != enrollment.writingDisplayMode else { return }
                Task { await settings.setWritingDisplayMode(mode, for: languageCode) }
            }
        )
    }

    /// Per-language layer labels joined, never a translated phrase per combination.
    private func modeLabel(_ mode: WritingDisplayMode, in language: LearningLanguage) -> String {
        mode.layers.map { layer in
            switch layer {
            case .standard: language.writingLayerLabel(.standard)
            case .phonetic: language.writingLayerLabel(.phonetic)
            case .transliterated: language.writingLayerLabel(.transliterated)
            }
        }
        .joined(separator: " + ")
    }
}

extension LearningLanguage {
    /// User-facing name of a writing layer, e.g. "Furigana" for Japanese phonetic.
    func writingLayerLabel(_ layer: WritingLayer) -> String {
        let languageKey: String
        switch code {
        case "ja": languageKey = "Ja"
        case "ko": languageKey = "Ko"
        case "pl": languageKey = "Pl"
        case "uk": languageKey = "Uk"
        case "zh-Hant": languageKey = "ZhHant"
        default: return ""
        }
        let layerKey: String
        switch layer {
        case .standard: layerKey = "Standard"
        case .phonetic: layerKey = "Phonetic"
        case .transliterated: layerKey = "Transliterated"
        }
        return NSLocalizedString("writingLayers\(languageKey)\(layerKey)", tableName: "Settings", comment: "")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LearningSettingsView(languageCode: "ja")
    }
    .previewDependencies()
    .preferredColorScheme(.dark)
}
#endif
