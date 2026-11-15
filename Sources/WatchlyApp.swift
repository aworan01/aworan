import SwiftUI

@main struct WatchlyApp: App {
    @StateObject private var library = LibraryStore()
    init() { TorrentEngine.cleanAbandonedSessions() }
    var body: some Scene {
        WindowGroup {
            Group {
                if library.activeID == nil { ProfilesView() }
                else { WatchlyHome() }
            }
            .environmentObject(library)
            .preferredColorScheme(.dark)
            .tint(.red)
        }
    }
}
