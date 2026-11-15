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
                Text("Playback troubleshooting").font(.title2)
                Button("Play Apple test stream") {
                    let url = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8"
                    playback = PlaybackRequest(media: MediaTitle(id: "watchly-test-hls", type: "movie", name: "Apple Bip Bop playback test"), source: StreamSource(title: "Apple HLS test · direct HTTPS", url: url))
                }
                Text("This direct stream bypasses torrents. In the player, open Audio, subtitles & playback → Diagnostics to inspect input bytes, codecs and decoded frames. A successful test does not establish support for every codec or video release.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Source provider").font(.title2)
                TextField("HTTPS Stremio-compatible provider base URL", text: $library.sourceProvider)
                Text("Use a base address without /manifest.json. Availability depends on the provider.").foregroundStyle(.secondary)
                Picker("Streaming storage", selection: $library.cacheGB) {
                    ForEach([1, 2, 4, 8, 16, 32], id: \.self) { Text("\($0) GB").tag($0) }
                }.frame(width: 500)
                Text("At the limit, downloading waits and the player offers a larger limit. Cached data and peer connections are preserved. Storage must be available on your Apple TV; cached files are removed when playback closes.").foregroundStyle(.secondary)
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
                Text("Watchly for Apple TV · Development preview 0.2.1").font(.headline)
                Text("Based on Watchly. Uses libtorrent, VLCKit, Cinemeta and IntroDB. Play media you have permission to access. This preview requires device validation.").font(.caption).foregroundStyle(.secondary)
            }.padding(60)
        }
        .confirmationDialog("Clear this profile’s watch history?", isPresented: $confirmClear) { Button("Clear history", role: .destructive) { library.clearHistory() } }
        .fullScreenCover(item: $playback) { request in PlayerScreen(request: request, library: library) }
    }
}
