import SwiftUI

/// Enroll in and drop learning languages. Turning a language on also makes
/// it active; the active one cannot be turned off, which also keeps at least
/// one language enrolled. A dropped language keeps its preferences for when
/// it is turned on again.
struct LanguagesSettingsView: View {
    @Environment(AppSettingsModel.self) private var settings

    var body: some View {
        List {
            Section {
                ForEach(LearningLanguage.all) { language in
                    Toggle(isOn: enrollment(of: language)) {
                        Text("\(language.emoji) \(language.nativeName)")
                    }
                    .disabled(!settings.canEdit || language.code == settings.activeLanguageCode)
                }
            } footer: {
                Text("languagesDescription", tableName: "Settings")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("languagesTitle", tableName: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .settingsSaveErrorAlert()
    }

    /// Toggling saves; the switch settles once the change is committed.
    private func enrollment(of language: LearningLanguage) -> Binding<Bool> {
        Binding(
            get: { settings.isEnrolled(language.code) },
            set: { isOn in
                guard isOn != settings.isEnrolled(language.code) else { return }
                Task {
                    if isOn {
                        await settings.enroll(language.code)
                    } else {
                        await settings.remove(language.code)
                    }
                }
            }
        )
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LanguagesSettingsView()
    }
    .previewDependencies()
    .preferredColorScheme(.dark)
}
#endif
