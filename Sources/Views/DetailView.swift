import SwiftUI

struct PlaybackRequest: Identifiable {
    let id = UUID()
    var media: MediaTitle
    var episode: Episode?
    var source: StreamSource
}

struct DetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let initial: MediaTitle
    @State private var detail: MediaTitle?
    @State private var season = 1
    @State private var showSources = false
    @State private var selectedEpisode: Episode?
    @State private var sources: [StreamSource] = []
    @State private var sourceError: String?
    @State private var detailError: String?
    @State private var loading = false
    @State private var playback: PlaybackRequest?
    private var media: MediaTitle { detail ?? initial }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack(alignment: .bottomLeading) {
                    Artwork(url: media.background ?? media.poster).frame(height: 500).clipped()
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 15) {
                        Text(media.name).font(.system(size: 52, weight: .bold))
                        Text(media.facts).foregroundStyle(.secondary)
                        Text((media.genres ?? []).joined(separator: " · ")).font(.headline)
                    }.padding(50)
                }
                VStack(alignment: .leading, spacing: 25) {
                    HStack(spacing: 24) {
                        if !media.isSeries { Button("Choose source") { choose(nil) } }
                        Button(library.hasSaved(media) ? "Remove from My List" : "Add to My List") { library.toggle(media) }
                    }
                    if let detailError { Text(detailError).foregroundStyle(.orange); Button("Retry details") { Task { await load() } } }
                    Text(media.description ?? "Loading details…").font(.body).fixedSize(horizontal: false, vertical: true)
                    if let cast = media.cast, !cast.isEmpty { Text("Cast: " + cast.prefix(8).joined(separator: ", ")).foregroundStyle(.secondary) }
                    if media.isSeries {
                        Picker("Season", selection: $season) { ForEach(Array(Set(media.episodes.map(\.season))).sorted(), id: \.self) { Text("Season \($0)").tag($0) } }.frame(width: 420)
                        ForEach(media.episodes.filter { $0.season == season }) { episode in
                            Button { choose(episode) } label: {
                                HStack(spacing: 25) {
                                    Artwork(url: episode.thumbnail).frame(width: 210, height: 118).clipped()
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("\(episode.label) · \(episode.title ?? "Episode \(episode.episode)")").font(.headline)
                                        Text(episode.overview ?? "").font(.caption).lineLimit(2)
                                        if let history = library.entry(media, episode: episode) { Text(history.completed ? "Watched" : "Resume available").font(.caption).foregroundStyle(.red) }
                                    }; Spacer()
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 60).padding(.bottom, 60)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showSources) {
            VStack(alignment: .leading, spacing: 24) {
                Text(selectedEpisode.map { "\(media.name) · \($0.label)" } ?? media.name).font(.title)
                if loading { ProgressView("Finding sources…") }
                if let sourceError { Text(sourceError).foregroundStyle(.orange); Button("Retry") { choose(selectedEpisode) } }
                if !loading && sources.isEmpty && sourceError == nil { Text("No sources were returned. Try another provider in Settings.") }
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(sources) { source in
                            Button {
                                showSources = false
                                playback = PlaybackRequest(media: media, episode: selectedEpisode, source: source)
                            } label: { Text(source.label).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                        }
                    }.padding(20)
                }
                Button("Close") { showSources = false }
            }.padding(60)
        }
        .fullScreenCover(item: $playback) { request in PlayerScreen(request: request, library: library) }
    }
    private func load() async {
        do { detail = try await Catalogue.shared.detail(initial); season = media.episodes.first?.season ?? 1; detailError = nil }
        catch { if !Task.isCancelled { detailError = error.localizedDescription } }
    }
    private func choose(_ episode: Episode?) {
        selectedEpisode = episode; sources = []; sourceError = nil; loading = true; showSources = true
        Task {
            do { sources = try await Catalogue.shared.sources(media, episode: episode, base: library.sourceProvider) }
            catch { sourceError = error.localizedDescription }
            loading = false
        }
    }
}
