import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var location = ""
    @State private var pin = ""
    @State private var pinMessage: String?
    @State private var playback: PlaybackRequest?
    @State private var confirmClear = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Settings").font(.largeTitle.bold())
                Text("Open a video or torrent").font(.title2)
                TextField("Magnet link, torrent URL, or video URL", text: $location)
                Button("Open") {
                    let input = location.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !input.isEmpty else { return }
                    let media = MediaTitle(id: input, type: "movie", name: "Opened video")
                    playback = PlaybackRequest(media: media, source: StreamSource(title: "Opened video", url: input))
                }
                Divider()
                Text("Source provider").font(.title2)
                TextField("HTTPS Stremio-compatible provider base URL", text: $library.sourceProvider)
                Text("Use a base address without /manifest.json. Availability depends on the provider.").foregroundStyle(.secondary)
                Picker("Streaming storage", selection: $library.cacheGB) {
                    ForEach([1, 2, 4, 8], id: \.self) { Text("\($0) GB").tag($0) }
                }.frame(width: 500)
                Text("The cache restarts at the limit. Playback can briefly rebuffer while peers reconnect. Changes apply to the next video.").foregroundStyle(.secondary)
                Divider()
                Text("Profile PIN").font(.title2)
                SecureField("Four digits, or leave blank to remove PIN", text: $pin)
                Button("Save PIN") {
                    if pin.isEmpty || (pin.count == 4 && pin.allSatisfy(\.isNumber)) { library.setPIN(pin); pin = ""; pinMessage = "PIN updated." }
                    else { pinMessage = "Enter exactly four digits." }
                }
                if let pinMessage { Text(pinMessage) }
                HStack(spacing: 30) { Button("Switch profile") { library.signOut() }; Button("Clear watch history") { confirmClear = true } }
                Divider()
                Text("Watchly for Apple TV · Development preview 0.1").font(.headline)
                Text("Based on Watchly. Uses libtorrent, VLCKit, Cinemeta and IntroDB. Play media you have permission to access. This preview requires device validation.").font(.caption).foregroundStyle(.secondary)
            }.padding(60)
        }
        .confirmationDialog("Clear this profile’s watch history?", isPresented: $confirmClear) { Button("Clear history", role: .destructive) { library.clearHistory() } }
        .fullScreenCover(item: $playback) { request in PlayerScreen(request: request, library: library) }
    }
}
