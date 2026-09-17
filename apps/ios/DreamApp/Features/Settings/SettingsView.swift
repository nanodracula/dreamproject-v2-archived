import SwiftUI

/// Screens reachable from the settings index.
enum SettingsRoute: Hashable {
    case general, interface, learning(languageCode: String), languages, sync, dev, terminal

    /// The sections offered straight from the navigation bar, with the label
    /// each shortcut shows.
    static let shortcuts: [(route: SettingsRoute, title: LocalizedStringResource, symbol: String)] = [
        (.general, LocalizedStringResource("itemsGeneral", table: "Settings"), "gearshape"),
        (.languages, LocalizedStringResource("languagesTitle", table: "Settings"), "globe"),
        (.interface, LocalizedStringResource("itemsInterface", table: "Settings"), "paintbrush"),
    ]
}

/// The settings index: a native inset-grouped list. In dark mode the system
/// grouped palette matches the old app's values exactly, so no colors are set.
struct SettingsView: View {
    let database: AppDatabase
    let retryObservation: () -> Void
    @Environment(AppSettingsModel.self) private var settings

    private var canAdd: Bool { settings.enrolledLanguages.count < LearningLanguage.all.count }

    var body: some View {
        List {
            if let loadError = settings.loadError {
                Section {
                    Text(loadError.localizedDescription)
                    Button {
                        retryObservation()
                    } label: {
                        Text("loadErrorRetry", tableName: "Settings")
                    }
                } header: {
                    Text("loadErrorTitle", tableName: "Settings")
                }
            }

            if case .starting = settings.observationStatus, settings.isLoaded {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }

            Section {
                if settings.isLoaded {
                    Picker(selection: activeLanguageSelection) {
                        ForEach(settings.enrolledLanguages) { language in
                            Text("\(language.emoji) \(language.nativeName)").tag(Optional(language.code))
                        }
                    } label: {
                        Text("learningLanguageLabel", tableName: "Settings")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(!settings.canEdit)
                } else if settings.loadError == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                NavigationLink(value: SettingsRoute.languages) {
                    Text(canAdd ? "languagesAdd" : "languagesManage", tableName: "Settings")
                }
                .disabled(!settings.isLoaded)
            } header: {
                Text("learningLanguageLabel", tableName: "Settings")
            }

            Section {
                SettingsIconLabel("itemsMyProfile", symbol: "person.crop.circle.fill", tint: 0xEB4E3D)
            }

            Section {
                NavigationLink(value: SettingsRoute.general) {
                    SettingsIconLabel("itemsGeneral", symbol: "gearshape.fill", tint: 0x8E8E93)
                }
                NavigationLink(value: SettingsRoute.interface) {
                    SettingsIconLabel("itemsInterface", symbol: "paintbrush.fill", tint: 0x5AC8FA, symbolSize: 16)
                }
                // An unsupported active language has no learning screen.
                if let language = settings.activeLanguage {
                    NavigationLink(value: SettingsRoute.learning(languageCode: language.code)) {
                        LabeledContent {
                            Text(language.nativeName)
                        } label: {
                            SettingsIconLabel("itemsLearning", symbol: "graduationcap.fill", tint: 0x3478F6, symbolSize: 15)
                        }
                    }
                } else {
                    SettingsIconLabel("itemsLearning", symbol: "graduationcap.fill", tint: 0x3478F6, symbolSize: 15)
                }
                NavigationLink(value: SettingsRoute.sync) {
                    SettingsIconLabel("itemsSync", symbol: "externaldrive.fill", tint: 0x34C759)
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.dev) {
                    SettingsIconLabel("itemsDev", symbol: "hammer.fill", tint: 0xFF9500)
                }
                NavigationLink(value: SettingsRoute.terminal) {
                    SettingsIconLabel("itemsTerminal", symbol: "terminal.fill", tint: 0x636366)
                }
            }

            Section {
                SettingsIconLabel("itemsFaq", symbol: "questionmark", tint: 0xFF9500, symbolSize: 15)
                SettingsIconLabel("itemsFeatures", symbol: "sparkles", tint: 0xAF52DE)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(24)
        .navigationTitle(Text("title", tableName: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .general: GeneralSettingsView()
            case .interface: InterfaceSettingsView()
            case .learning(let languageCode): LearningSettingsView(languageCode: languageCode)
            case .languages: LanguagesSettingsView()
            case .sync: SyncSettingsView()
            case .dev: DevView(database: database)
            case .terminal: TerminalView()
            }
        }
        // Declared outside `navigationDestination`, so every pushed screen inherits it.
        .scrollIndicators(.hidden)
        .settingsSaveErrorAlert()
    }

    /// Selecting saves; the picker moves once the change is committed.
    private var activeLanguageSelection: Binding<String?> {
        Binding(
            get: { settings.activeLanguageCode },
            set: { code in
                guard let code, code != settings.activeLanguageCode else { return }
                Task { await settings.setActiveLanguage(code) }
            }
        )
    }
}

extension View {
    /// Presents the last failed settings save as a dismissible alert. Attach
    /// to every screen that edits settings, since alerts present only from
    /// the visible screen.
    func settingsSaveErrorAlert() -> some View {
        modifier(SettingsSaveErrorAlert())
    }
}

private struct SettingsSaveErrorAlert: ViewModifier {
    @Environment(AppSettingsModel.self) private var settings

    func body(content: Content) -> some View {
        content.alert(
            Text("saveErrorTitle", tableName: "Settings"),
            isPresented: Binding(
                get: { settings.saveError != nil },
                set: { if !$0 { settings.saveError = nil } }
            ),
            presenting: settings.saveError
        ) { _ in
        } message: { message in
            Text(message)
        }
    }
}

/// Settings.app style row label: a colored 30pt tile with a white symbol.
struct SettingsIconLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: UInt32
    let symbolSize: CGFloat

    init(_ title: LocalizedStringKey, symbol: String, tint: UInt32, symbolSize: CGFloat = 18) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.symbolSize = symbolSize
    }

    var body: some View {
        Label {
            Text(title, tableName: "Settings")
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Layout.tileSize, height: Layout.tileSize)
                .background(Color(hex: tint), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .labelStyle(SettingsRowLabelStyle())
        .frame(minHeight: Layout.tileSize)
        // The separator starts at the text, not the tile.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + Layout.tileSize + Layout.gap }
    }

    private enum Layout {
        static let tileSize: CGFloat = 30
        static let gap: CGFloat = 14
    }
}

private struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
            configuration.title
        }
    }
}

#if DEBUG
#Preview {
    SettingsPreview()
}

private struct SettingsPreview: View {
    @State private var preview = PreviewSupport()

    var body: some View {
        NavigationStack {
            SettingsView(database: preview.dependencies.database, retryObservation: {
                preview.session.restartObservation()
            })
        }
        .environment(preview.session.settings)
        .task { try? await preview.session.start() }
        .onDisappear { preview.session.stop() }
        .preferredColorScheme(.dark)
    }
}
#endif
