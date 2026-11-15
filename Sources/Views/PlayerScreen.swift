import SwiftUI
import Combine
import VLCKitSPM

@MainActor final class PlaybackModel: ObservableObject {
    let player = VLCMediaPlayer()
    @Published var message = "Preparing video…"
    @Published var error: String?
    @Published var ready = false
    @Published var files: [TorrentFile] = []
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var playing = false
    @Published var ended = false
    @Published var segments: SkipSegments?
    @Published var speed: Float = 1
    let request: PlaybackRequest
    private let library: LibraryStore
    private var engine: TorrentEngine?
    private var server: RangeServer?
    private var task: Task<Void, Never>?
    private var segmentTask: Task<Void, Never>?
    private var resumeApplied = false
    private var ticks = 0
    private var closed = false
    private var selectedSource: StreamSource
    init(request: PlaybackRequest, library: LibraryStore) {
        self.request = request; self.library = library; selectedSource = request.source
    }
    func begin() {
        guard task == nil else { return }
        segmentTask = Task {
            let result = await Catalogue.shared.segments(request.media, episode: request.episode)
            if !Task.isCancelled && !closed { segments = result }
        }
        task = Task {
            do {
                guard let location = request.source.location else { throw WatchlyError.message("This source has no playable location.") }
                try Task.checkCancellation()
                let torrent = location.lowercased().hasPrefix("magnet:") || URL(string: location)?.pathExtension.lowercased() == "torrent"
                if !torrent {
                    guard let url = URL(string: location), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                        throw WatchlyError.message("This source’s URL type is not supported.")
                    }
                    play(url); return
                }
                message = "Finding torrent peers and metadata…"
                let engine = try TorrentEngine(cacheGB: library.cacheGB)
                self.engine = engine
                try await engine.open(location)
                let deadline = Date().addingTimeInterval(90)
                while Date() < deadline {
                    try Task.checkCancellation()
                    if let all = try await engine.files() {
                        let videos = all.filter { $0.isVideo && $0.size > 0 }
                        guard !videos.isEmpty else { throw WatchlyError.message("No supported video files were found in this torrent.") }
                        if let index = request.source.fileIdx, let file = videos.first(where: { $0.id == index }) { try await select(file); return }
                        if let episode = request.episode {
                            let matches = videos.filter { $0.matches(episode) }
                            if matches.count == 1 { try await select(matches[0]); return }
                        } else if let largest = videos.max(by: { $0.size < $1.size }) { try await select(largest); return }
                        if videos.count == 1 { try await select(videos[0]); return }
                        files = videos; message = "Choose the episode file"; return
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                throw WatchlyError.message("No metadata arrived within 90 seconds. Try another source with active seeders.")
            } catch is CancellationError { }
            catch { if !closed { self.error = error.localizedDescription } }
        }
    }
    func choose(_ file: TorrentFile) {
        files = []
        task = Task { do { try await select(file) } catch { if !closed { self.error = error.localizedDescription } } }
    }
    private func select(_ file: TorrentFile) async throws {
        guard let engine else { return }
        try Task.checkCancellation()
        try await engine.select(file)
        selectedSource.fileIdx = file.id
        message = "Buffering \((file.name as NSString).lastPathComponent)…"
        let server = RangeServer(engine: engine, file: file)
        server.onError = { [weak self] message in Task { @MainActor in if self?.closed == false { self?.error = message } } }
        self.server = server
        let url = try await server.start()
        try Task.checkCancellation()
        play(url)
    }
    private func play(_ url: URL) {
        guard !closed else { return }
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=2000")
        player.media = media
        ready = true
        // PlayerSurface attaches the drawable before calling startVideo().
    }
    func startVideo() { if ready && !closed { player.play() } }
    func tick() {
        guard ready && !closed else { return }
        let at = Double(player.time.intValue) / 1000
        let length = Double(player.media?.length.intValue ?? 0) / 1000
        if at.isFinite && at >= 0 { position = at }
        if length.isFinite && length > 0 { duration = length }
        playing = player.isPlaying
        if !resumeApplied && duration > 0 && player.isSeekable {
            resumeApplied = true
            if let history = library.entry(request.media, episode: request.episode), !history.completed, history.position > 5 {
                seek(to: min(history.position, duration - 1))
            }
        }
        if player.state == .error { error = "The player could not decode or read this source. Try another release." }
        if player.state == .ended { ended = true; position = duration; save() }
        ticks += 1
        if ticks % 5 == 0 { save() }
    }
    func save() { library.record(request.media, episode: request.episode, source: selectedSource, position: position, duration: duration) }
    func toggle() { if player.isPlaying { player.pause() } else { player.play() }; playing = player.isPlaying }
    func pause() { if player.isPlaying { player.pause() }; save() }
    func seek(to seconds: Double) {
        guard duration > 0, player.isSeekable else { return }
        let clamped = max(0, min(seconds, duration - 0.5))
        player.position = Float(clamped / duration)
        position = clamped; ended = false
    }
    func setSpeed(_ value: Float) { player.rate = value; speed = value }
    func close() {
        guard !closed else { return }
        closed = true; save(); task?.cancel(); segmentTask?.cancel(); engine?.cancel(); server?.stop()
        player.stop(); player.drawable = nil
        let old = engine; engine = nil
        Task { await old?.stop() }
    }
    var audioTracks: [(Int32, String)] {
        zip(player.audioTrackIndexes, player.audioTrackNames).compactMap { index, name in
            guard let index = index as? NSNumber, let name = name as? String else { return nil }; return (index.int32Value, name)
        }
    }
    var subtitleTracks: [(Int32, String)] {
        zip(player.videoSubTitlesIndexes, player.videoSubTitlesNames).compactMap { index, name in
            guard let index = index as? NSNumber, let name = name as? String else { return nil }; return (index.int32Value, name)
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let model: PlaybackModel
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .black
        model.player.drawable = view
        model.startVideo()
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { }
}

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: PlaybackModel
    @State private var controls = true
    @State private var tracks = false
    @State private var panel = "Info"
    @State private var preview: Double?
    @State private var lastInteraction = Date()
    @FocusState private var transportFocus: String?
    @State private var nextSources: [StreamSource] = []
    @State private var nextError: String?
    @State private var loadingNext = false
    @State private var nextRequest: PlaybackRequest?
    @State private var nextSheet = false
    private let library: LibraryStore
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    init(request: PlaybackRequest, library: LibraryStore) {
        self.library = library
        _model = StateObject(wrappedValue: PlaybackModel(request: request, library: library))
    }
    private var nextEpisode: Episode? {
        guard let episode = model.request.episode, let index = model.request.media.episodes.firstIndex(where: { $0.id == episode.id }) else { return nil }
        let episodes = model.request.media.episodes
        return episodes.indices.contains(index + 1) ? episodes[index + 1] : nil
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.ready { PlayerSurface(model: model).ignoresSafeArea() }
            if let error = model.error {
                VStack(spacing: 28) { Text("Playback unavailable").font(.title); Text(error).multilineTextAlignment(.center); Button("Back") { dismiss() } }.padding(80).background(.black.opacity(0.9))
            } else if !model.ready {
                VStack(spacing: 24) {
                    if model.files.isEmpty { ProgressView() }
                    Text(model.message)
                    if !model.files.isEmpty {
                        ScrollView { VStack(spacing: 20) { ForEach(model.files) { file in Button(file.name) { model.choose(file) } } }.padding(30) }.frame(maxHeight: 500)
                    }
                    Button("Cancel") { dismiss() }
                }.padding(60)
            } else if controls || model.ended {
                transport
            } else {
                // A focusable transparent surface keeps Select/remote events usable.
                Color.clear.focusable().onTapGesture { reveal() }
            }
            if model.ready && model.error == nil && !tracks && !nextSheet {
                VStack { Spacer(); HStack { Spacer(); skipButtons }.padding(.bottom, controls || model.ended ? 370 : 65).padding(.trailing, 65) }
            }
        }
        .task { model.begin() }
        .onReceive(timer) { _ in
            model.tick()
            if controls && model.playing && !model.ended && !tracks && !nextSheet && preview == nil && Date().timeIntervalSince(lastInteraction) > 7 {
                controls = false
            }
        }
        .onPlayPauseCommand { model.toggle(); reveal() }
        .onChange(of: transportFocus) { _ in touch() }
        .onMoveCommand { direction in
            touch()
            if !controls {
                if direction == .left { model.seek(to: model.position - 10) }
                else if direction == .right { model.seek(to: model.position + 10) }
                else if direction == .up { tracks = true }
                reveal()
            }
        }
        .onExitCommand {
            if preview != nil { preview = nil; touch() }
            else if tracks { tracks = false; reveal() }
            else if controls && model.ready && !model.ended { controls = false }
            else { dismiss() }
        }
        .onChange(of: scenePhase) { phase in if phase != .active { model.pause() } }
        .onDisappear { model.close() }
        .sheet(isPresented: $tracks, onDismiss: { reveal() }) { playbackPanel }
        .sheet(isPresented: $nextSheet) {
            VStack(spacing: 24) {
                Text("Next episode").font(.title)
                if loadingNext { ProgressView() }
                if let nextError { Text(nextError) }
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(nextSources) { source in
                            Button(source.label) {
                                nextSheet = false
                                model.close()
                                nextRequest = PlaybackRequest(media: model.request.media, episode: nextEpisode, source: source)
                            }
                        }
                    }.padding(30)
                }
                Button("Cancel") { nextSheet = false }
            }.padding(60)
        }
        .fullScreenCover(item: $nextRequest, onDismiss: { dismiss() }) { request in PlayerScreen(request: request, library: library) }
    }
    private func touch() { lastInteraction = Date() }
    private func reveal() { controls = true; touch() }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text(model.request.media.name).font(.system(size: 44, weight: .bold))
            if let episode = model.request.episode { Text("\(episode.label) · \(episode.title ?? "")").foregroundStyle(.secondary) }
            if model.duration == 0 { ProgressView("Buffering…") }
            HStack(spacing: 24) {
                Button { model.toggle(); touch() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill") }
                    .focused($transportFocus, equals: "play").accessibilityLabel(model.playing ? "Pause" : "Play")
                Text(time(preview ?? model.position)).monospacedDigit().frame(width: 130)
                Button {
                    if let target = preview { model.seek(to: target); preview = nil }
                    else { preview = model.position }
                    touch()
                } label: {
                    VStack(spacing: 10) {
                        ProgressView(value: min(1, (preview ?? model.position) / max(1, model.duration))).tint(.red)
                        Text(preview == nil ? "Select to seek" : "← / → seek · Select to play · Back to cancel").font(.caption2)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .focused($transportFocus, equals: "timeline")
                .disabled(model.duration <= 0 || !model.player.isSeekable)
                .onMoveCommand { direction in
                    guard direction == .left || direction == .right else { return }
                    preview = max(0, min(model.duration - 0.5, (preview ?? model.position) + (direction == .left ? -10 : 10)))
                    touch()
                }
                Text("−" + time(max(0, model.duration - (preview ?? model.position)))).monospacedDigit().frame(width: 130)
            }
            HStack(spacing: 24) {
                Button { model.seek(to: model.position - 10); touch() } label: { Image(systemName: "gobackward.10") }.accessibilityLabel("Back 10 seconds")
                Button { model.seek(to: model.position + 10); touch() } label: { Image(systemName: "goforward.10") }.accessibilityLabel("Forward 10 seconds")
                Button("Audio, subtitles & playback") { preview = nil; tracks = true; touch() }
                if nextEpisode != nil { Button("Next episode") { loadNext() } }
                Spacer()
                Button("Close") { dismiss() }
            }.font(.system(size: 23))
        }.padding(60)
        .background(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private var skipButtons: some View {
        if let intro = model.segments?.intro(at: model.position, duration: model.duration), model.player.isSeekable {
            Button("Skip Intro") { model.seek(to: intro.end); touch() }
        }
        if let segments = model.segments, let outro = segments.outro(at: model.position, duration: model.duration), model.player.isSeekable {
            Button("Skip Outro / Credits") { model.seek(to: segments.outroDestination(outro)); touch() }
            if !controls && nextEpisode != nil { Button("Next Episode") { loadNext() } }
        }
    }

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(model.request.media.name).font(.title.bold())
            Picker("Playback settings", selection: $panel) {
                ForEach(["Info", "Audio", "Subtitles", "Playback"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if panel == "Info" {
                        Text(model.request.episode?.label ?? "Movie").font(.headline)
                        Text(model.request.media.facts).foregroundStyle(.secondary)
                        Text(model.request.episode?.overview ?? model.request.media.description ?? "No synopsis available.")
                        Text("Intro/outro timing: IntroDB · Buttons appear only when timing is available for this title. Release timings can vary.").font(.caption).foregroundStyle(.secondary)
                    } else if panel == "Audio" {
                        if model.audioTracks.isEmpty { Text("No selectable audio tracks.") }
                        ForEach(model.audioTracks, id: \.0) { track in
                            Button((model.player.currentAudioTrackIndex == track.0 ? "✓ " : "") + track.1) { model.player.currentAudioTrackIndex = track.0; tracks = false }
                        }
                    } else if panel == "Subtitles" {
                        Button(model.player.currentVideoSubTitleIndex == -1 ? "✓ Off" : "Off") { model.player.currentVideoSubTitleIndex = -1; tracks = false }
                        ForEach(model.subtitleTracks.filter { $0.0 >= 0 }, id: \.0) { track in
                            Button((model.player.currentVideoSubTitleIndex == track.0 ? "✓ " : "") + track.1) { model.player.currentVideoSubTitleIndex = track.0; tracks = false }
                        }
                    } else {
                        Text("Playback speed").font(.headline)
                        HStack(spacing: 24) {
                            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                                Button((model.speed == speed ? "✓ " : "") + String(format: "%g×", Double(speed))) { model.setSpeed(speed) }
                            }
                        }
                        if nextEpisode != nil { Button("Next episode") { tracks = false; loadNext() } }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(30)
            }
            Button("Back to video") { tracks = false }
        }.padding(60)
        .onExitCommand { tracks = false }
    }
    private func loadNext() {
        guard let nextEpisode else { return }
        nextSheet = true; nextSources = []; nextError = nil; loadingNext = true
        Task {
            do {
                nextSources = try await Catalogue.shared.sources(model.request.media, episode: nextEpisode, base: library.sourceProvider)
                if nextSources.isEmpty { nextError = "No sources found for this episode." }
            } catch { nextError = error.localizedDescription }
            loadingNext = false
        }
    }
    private func time(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
