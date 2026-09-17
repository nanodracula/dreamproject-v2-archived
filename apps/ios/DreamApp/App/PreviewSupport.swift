#if DEBUG
import SwiftUI

/// Each preview owns its in-memory infrastructure and explicitly scoped session.
@MainActor
final class PreviewSupport {
    let dependencies: AppDependencies
    let session: AppSession

    init() {
        dependencies = AppDependencies(database: try! AppDatabase.openInMemory())
        session = AppSession(dependencies: dependencies)
    }
}

extension View {
    func previewDependencies() -> some View {
        modifier(PreviewDependencies())
    }
}

private struct PreviewDependencies: ViewModifier {
    @State private var preview = PreviewSupport()

    func body(content: Content) -> some View {
        content
            .environment(preview.session.settings)
            .task { try? await preview.session.start() }
            .onDisappear { preview.session.stop() }
    }
}
#endif
