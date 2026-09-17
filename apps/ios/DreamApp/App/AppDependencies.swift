import Foundation
import Supabase

/// Process-wide infrastructure, retained by AppDelegate.
@MainActor
final class AppDependencies {
    let database: AppDatabase
    let deviceSettings: DeviceSettings
    /// The shared Supabase client. Feature request clients, such as
    /// `CardTitleGeneration`, are built from it.
    let supabase: SupabaseClient
    let supabaseSession: SupabaseSession
    let mediaUploader: MediaUploader
    let mediaCache: MediaCache
    let pronunciation: Pronunciation

    init(
        database: AppDatabase,
        deviceSettings: DeviceSettings = DeviceSettings(),
        supabase: SupabaseClient = .live()
    ) {
        self.database = database
        self.deviceSettings = deviceSettings
        self.supabase = supabase
        supabaseSession = SupabaseSession(auth: supabase.auth)
        mediaUploader = MediaUploader(supabase: supabase, session: supabaseSession)
        mediaCache = MediaCache(supabase: supabase)
        pronunciation = Pronunciation(cache: mediaCache)
    }

    /// Opens and migrates the database off the main actor, then wires the
    /// services on the main actor. Construction does not wait for network IO.
    static func live() async throws -> AppDependencies {
        let database = try await Task.detached(priority: .userInitiated) {
            try AppDatabase.openPersistent()
        }.value
        try Task.checkCancellation()
        return AppDependencies(database: database)
    }
}
