import Foundation

/// One user's repositories and observation lifetime. Infrastructure outlives this session.
@MainActor
final class AppSession {
    let settingsRepository: SettingsRepository
    let settings: AppSettingsModel
    private var run: ObservationRun?

    init(dependencies: AppDependencies, userID: UUID = AppDatabase.guestUserID) {
        settingsRepository = SettingsRepository(writer: dependencies.database.writer, userID: userID)
        settings = AppSettingsModel(repository: settingsRepository)
    }

    /// Waits only for the first committed snapshot. The observation task continues independently.
    func start() async throws {
        stop()
        try Task.checkCancellation()
        let run = ObservationRun()
        self.run = run
        settings.setObservationStatus(.starting)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.startup = continuation
                observe(run)
            }
            try Task.checkCancellation()
            guard self.run === run else { throw CancellationError() }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.run === run else { return }
                self?.stop()
            }
        }
    }

    func restartObservation() {
        stop()
        let run = ObservationRun()
        self.run = run
        settings.setObservationStatus(.starting)
        observe(run)
    }

    func stop() {
        run?.cancel()
        run = nil
        settings.setObservationStatus(.stopped)
    }

    isolated deinit {
        run?.cancel()
        settings.setObservationStatus(.stopped)
    }

    private func observe(_ run: ObservationRun) {
        // Never promote self to a strong reference across the iterator's suspension.
        run.task = Task { [weak self, weak run, repository = settingsRepository] in
            do {
                for try await snapshot in repository.observeSnapshot() {
                    guard !Task.isCancelled else { return }
                    self?.receive(snapshot, run: run)
                }
                if !Task.isCancelled { self?.fail(ObservationEnded(), run: run) }
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error, run: run)
            }
        }
    }

    private func receive(_ snapshot: SettingsSnapshot, run: ObservationRun?) {
        guard let run, self.run === run else { return }
        settings.apply(snapshot)
        run.finishStartup(.success(()))
    }

    private func fail(_ error: any Error, run: ObservationRun?) {
        guard let run, self.run === run else { return }
        settings.setObservationStatus(.failed(error))
        run.finishStartup(.failure(error))
        run.task = nil
    }
}

@MainActor
private final class ObservationRun {
    var task: Task<Void, Never>?
    var startup: CheckedContinuation<Void, any Error>?

    func finishStartup(_ result: Result<Void, any Error>) {
        let continuation = startup
        startup = nil
        continuation?.resume(with: result)
    }

    func cancel() {
        task?.cancel()
        task = nil
        finishStartup(.failure(CancellationError()))
    }
}

private struct ObservationEnded: LocalizedError {
    var errorDescription: String? { "Settings observation ended. Please retry." }
}
