import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var infrastructure: AppDependencies?
    private var infrastructureTask: Task<AppDependencies, any Error>?

    /// Share successful construction across scene lifetimes; failed attempts remain retryable.
    func dependencies() async throws -> AppDependencies {
        if let infrastructure { return infrastructure }
        if infrastructureTask == nil {
            infrastructureTask = Task {
                let dependencies = try await AppDependencies.live()
                infrastructure = dependencies
                return dependencies
            }
        }
        defer { infrastructureTask = nil }
        return try await infrastructureTask!.value
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene,
              let app = UIApplication.shared.delegate as? AppDelegate else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = RootViewController(loadDependencies: { try await app.dependencies() })
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        (window?.rootViewController as? RootViewController)?.stop()
        window?.rootViewController = nil
        window = nil
    }
}
