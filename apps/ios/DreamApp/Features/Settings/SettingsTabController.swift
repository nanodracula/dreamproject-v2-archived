import Observation
import SwiftUI

/// The Settings feature owns its navigation state, including external shortcuts.
final class SettingsTabController: UIHostingController<AnyView> {
    private let navigation = SettingsNavigation()

    init(database: AppDatabase, session: AppSession) {
        super.init(rootView: AnyView(
            SettingsRoot(navigation: navigation, database: database, retryObservation: { [weak session] in
                session?.restartObservation()
            })
            .environment(session.settings)
        ))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func open(_ route: SettingsRoute) {
        navigation.path = [route]
    }
}

@Observable
private final class SettingsNavigation {
    var path: [SettingsRoute] = []
}

private struct SettingsRoot: View {
    @Bindable var navigation: SettingsNavigation
    let database: AppDatabase
    let retryObservation: () -> Void

    var body: some View {
        NavigationStack(path: $navigation.path) {
            SettingsView(database: database, retryObservation: retryObservation)
        }
    }
}
