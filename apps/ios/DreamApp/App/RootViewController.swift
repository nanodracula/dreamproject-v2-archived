import SwiftUI
import UIKit

/// Swaps exactly one child as local startup moves from loading to tabs or retry.
final class RootViewController: UIViewController {
    private let loadDependencies: () async throws -> AppDependencies
    private var startupTask: Task<Void, Never>?
    private var startupID = UUID()
    private var session: AppSession?

    init(loadDependencies: @escaping () async throws -> AppDependencies) {
        self.loadDependencies = loadDependencies
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(AppColors.background)
        start()
    }

    func stop() {
        startupID = UUID()
        startupTask?.cancel()
        startupTask = nil
        session?.stop()
        session = nil
    }

    isolated deinit {
        startupTask?.cancel()
        session?.stop()
    }

    private func start() {
        stop()
        show(LoadingViewController())
        let id = startupID
        startupTask = Task { [weak self, loadDependencies] in
            do {
                let dependencies = try await loadDependencies()
                try Task.checkCancellation()
                guard self?.startupID == id else { return }
                let session = AppSession(dependencies: dependencies)
                self?.session = session
                try await session.start()
                try Task.checkCancellation()
                guard self?.startupID == id else { return }
                self?.show(AppTabBarController(dependencies: dependencies, session: session))
            } catch {
                guard !Task.isCancelled, self?.startupID == id else { return }
                self?.session?.stop()
                self?.session = nil
                self?.show(StartupErrorViewController(error: error) { [weak self] in self?.start() })
            }
        }
    }

    private func show(_ child: UIViewController) {
        for previous in children {
            previous.willMove(toParent: nil)
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }
}

private final class LoadingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(AppColors.launchBackground)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()
    }
}

private final class StartupErrorViewController: UIViewController {
    private let error: any Error
    private let retry: () -> Void

    init(error: any Error, retry: @escaping () -> Void) {
        self.error = error
        self.retry = retry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(AppColors.background)
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "exclamationmark.triangle")
        configuration.text = String(localized: "startupErrorTitle", table: "App")
        configuration.secondaryText = error.localizedDescription
        configuration.button.title = String(localized: "startupRetry", table: "App")
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.retry() }
        contentUnavailableConfiguration = configuration
    }
}
