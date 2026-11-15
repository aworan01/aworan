import SwiftUI

struct Artwork: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
        placeholder: { ZStack { Color(white: 0.12); Image(systemName: "film").font(.largeTitle).foregroundStyle(.gray) } }
        .clipped()
    }
}

struct ProfilesView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var name = ""
    @State private var selected: Profile?
    @State private var pin = ""
    @State private var wrongPIN = false
    var body: some View {
        VStack(spacing: 38) {
            Text("WATCHLY").font(.system(size: 30, weight: .black)).foregroundStyle(.red)
            Text("Who’s watching?").font(.system(size: 50, weight: .bold))
            HStack(spacing: 30) {
                ForEach(library.profiles) { profile in
                    Button {
                        if profile.pinDigest != nil { pin = ""; selected = profile }
                        else { _ = library.select(profile) }
                    } label: {
                        VStack(spacing: 14) {
                            Image(systemName: profile.symbol).font(.system(size: 60)).frame(width: 130, height: 120)
                            Text(profile.name)
                            if profile.pinDigest != nil { Image(systemName: "lock.fill").font(.caption) }
                        }.padding(20)
                    }
                }
            }
            if library.profiles.count < 8 {
                HStack { TextField("New profile name", text: $name).frame(width: 360); Button("Add profile") { library.addProfile(name: name); name = "" } }
            }
        }
        .sheet(item: $selected) { profile in
            VStack(spacing: 24) {
                Text(profile.name).font(.largeTitle)
                SecureField("Four-digit PIN", text: $pin).frame(width: 400)
                if wrongPIN { Text("Incorrect PIN").foregroundStyle(.red) }
                Button("Continue") { if library.select(profile, pin: pin) { selected = nil; wrongPIN = false } else { wrongPIN = true } }
                Button("Cancel") { selected = nil; wrongPIN = false }
            }
        }
    }
}

struct WatchlyHome: View {
    var body: some View {
        TabView {
            NavigationStack { BrowseView(type: nil) }.tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { BrowseView(type: "movie") }.tabItem { Label("Movies", systemImage: "film") }
            NavigationStack { BrowseView(type: "series") }.tabItem { Label("Series", systemImage: "tv") }
            NavigationStack { SearchView() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView() }.tabItem { Label("My List", systemImage: "bookmark.fill") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct TitleCard: View {
    var title: MediaTitle
    var body: some View {
        NavigationLink { DetailView(initial: title) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Artwork(url: title.poster).frame(width: 190, height: 280).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(title.name).font(.headline).lineLimit(1).frame(width: 190, alignment: .leading)
                Text(title.releaseInfo ?? "").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }.buttonStyle(.card)
    }
}

struct Shelf: View {
    var name: String
    var titles: [MediaTitle]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(name).font(.title2.bold()).padding(.horizontal, 60)
            ScrollView(.horizontal) { LazyHStack(spacing: 26) { ForEach(titles) { TitleCard(title: $0) } }.padding(.horizontal, 60).padding(.vertical, 20) }
        }
    }
}

struct BrowseView: View {
    @EnvironmentObject private var library: LibraryStore
    let type: String?
    @State private var movies: [MediaTitle] = []
    @State private var series: [MediaTitle] = []
    @State private var error: String?
    @State private var loading = false
    @State private var genre = "All"
    private let genres = ["All", "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Text("WATCHLY").font(.system(size: 38, weight: .black)).foregroundStyle(.red)
                    Spacer()
                    if type != nil { Picker("Genre", selection: $genre) { ForEach(genres, id: \.self) { Text($0).tag($0) } }.frame(width: 360) }
                }.padding(.horizontal, 60)
                if loading { ProgressView("Loading catalogue…").padding(60) }
                if let error { Text(error).foregroundStyle(.orange).padding(.horizontal, 60); Button("Retry") { Task { await load() } }.padding(.horizontal, 60) }
                if type == nil && !library.history.filter({ !$0.completed }).isEmpty {
                    VStack(alignment: .leading) {
                        Text("Continue watching").font(.title2.bold()).padding(.horizontal, 60)
                        ScrollView(.horizontal) {
                            HStack(spacing: 24) {
                                ForEach(library.history.filter { !$0.completed }) { item in
                                    NavigationLink { DetailView(initial: item.media) } label: {
                                        VStack(alignment: .leading) {
                                            Artwork(url: item.media.background ?? item.media.poster).frame(width: 330, height: 186).clipped()
                                            Text(item.media.name).lineLimit(1)
                                            Text(item.episode?.label ?? "Movie").font(.caption)
                                            ProgressView(value: min(1, item.position / max(1, item.duration)))
                                        }.frame(width: 330).padding(10)
                                    }.buttonStyle(.card)
                                }
                            }.padding(.horizontal, 60).padding(.vertical, 20)
                        }
                    }
                }
                if !movies.isEmpty { Shelf(name: "Popular movies", titles: movies) }
                if !series.isEmpty { Shelf(name: "Popular series", titles: series) }
            }.padding(.vertical, 35)
        }
        .task(id: genre) { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let filter = genre == "All" ? nil : genre
            if type != "series" { movies = try await Catalogue.shared.shelf(type: "movie", genre: filter) }
            if type != "movie" { series = try await Catalogue.shared.shelf(type: "series", genre: filter) }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

struct SearchView: View {
    @State private var query = ""
    @State private var movies: [MediaTitle] = []
    @State private var series: [MediaTitle] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Search movies and series", text: $query).padding(.horizontal, 60)
                if loading { ProgressView("Searching…").padding(.horizontal, 60) }
                if let error { Text(error).foregroundStyle(.orange).padding(.horizontal, 60) }
                if !movies.isEmpty { Shelf(name: "Movies", titles: movies) }
                if !series.isEmpty { Shelf(name: "Series", titles: series) }
                if !loading && movies.isEmpty && series.isEmpty && !query.isEmpty && error == nil { Text("No titles found.").padding(60) }
            }.padding(.vertical, 40)
        }.task(id: query) {
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { movies = []; series = []; loading = false; return }
            loading = true; error = nil
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                async let filmResults = Catalogue.shared.search(query, type: "movie")
                async let seriesResults = Catalogue.shared.search(query, type: "series")
                let results = try await (filmResults, seriesResults)
                try Task.checkCancellation()
                movies = results.0; series = results.1; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                if library.saved.isEmpty { Text("Save a title from its details page to add it to My List.").padding(60) }
                else { Shelf(name: "My List", titles: library.saved) }
                if !library.history.isEmpty {
                    Text("Watch history").font(.title2.bold()).padding(.horizontal, 60)
                    ForEach(library.history) { entry in
                        NavigationLink { DetailView(initial: entry.media) } label: {
                            HStack { Text(entry.media.name); Text(entry.episode?.label ?? "").foregroundStyle(.secondary); Spacer(); Text(entry.completed ? "Watched" : "In progress") }
                        }.padding(.horizontal, 60)
                    }
                }
            }.padding(.vertical, 40)
        }
    }
}
