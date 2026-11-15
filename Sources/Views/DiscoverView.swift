import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var titles: [MediaTitle] = []
    @State private var loading = false
    @State private var error: String?
    @State private var browsing = false
    private var selection: DiscoverSelection { library.discover }
    private var requestKey: String { "\(library.activeID ?? "")/\(selection.type)/\(selection.genre)" }
    private var ordered: [MediaTitle] { selection.ordered(titles) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Discover").font(.system(size: 48, weight: .bold))
                    Spacer()
                    Text("Cinemeta · Popular").foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    Menu {
                        Picker("Type", selection: $library.discover.type) {
                            Text("Movies").tag("movie")
                            Text("Series").tag("series")
                        }
                    } label: { Label(selection.type == "movie" ? "Movies" : "Series", systemImage: "film.stack") }
                    Menu {
                        Picker("Genre", selection: $library.discover.genre) {
                            ForEach(DiscoverSelection.genres, id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Label(selection.genre, systemImage: "line.3.horizontal.decrease") }
                    Menu {
                        Picker("Sort loaded titles", selection: $library.discover.sort) {
                            ForEach(DiscoverSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Label(selection.sort.rawValue, systemImage: "arrow.up.arrow.down") }
                    Button("Browse genres") { browsing = true }
                    Button("Reset") { library.discover = DiscoverSelection() }
                }.font(.system(size: 22)).focusSection()
                Text("\(titles.count) loaded titles · Sorting applies to this catalogue’s loaded results.")
                    .font(.caption).foregroundStyle(.secondary)
                if loading { ProgressView("Loading catalogue…").padding(40) }
                if let error {
                    Text(error).foregroundStyle(.orange)
                    Button("Retry") { Task { await load() } }
                }
                if !loading && error == nil && titles.isEmpty { Text("No titles for these filters. Try another genre.") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 28)], alignment: .leading, spacing: 36) {
                    ForEach(ordered) { TitleCard(title: $0) }
                }.padding(.vertical, 20)
            }.padding(60)
        }
        .background(Color(white: 0.035))
        .task(id: requestKey) { await load() }
        .sheet(isPresented: $browsing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Browse genres").font(.largeTitle.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 24)], spacing: 24) {
                        ForEach(DiscoverSelection.genres, id: \.self) { genre in
                            Button(genre) { library.discover.genre = genre; browsing = false }
                        }
                    }
                    Button("Close") { browsing = false }
                }.padding(70)
            }
        }
    }
    private func load() async {
        let key = requestKey
        let pick = selection
        loading = true; error = nil; titles = []
        do {
            let result = try await Catalogue.shared.shelf(type: pick.type, genre: pick.genre == "All" ? nil : pick.genre)
            try Task.checkCancellation()
            guard key == requestKey else { return }
            var seen = Set<String>()
            titles = result.filter { seen.insert($0.id).inserted }
            loading = false
        } catch {
            guard !Task.isCancelled, key == requestKey else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}

struct FeaturedTitle: View {
    let title: MediaTitle
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: title.background ?? title.poster).frame(height: 480).clipped()
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 18) {
                Text("WATCHLY").font(.headline.weight(.black)).foregroundStyle(.red)
                Text(title.name).font(.system(size: 54, weight: .bold)).lineLimit(2)
                Text(title.facts).foregroundStyle(.secondary)
                Text(title.description ?? "Explore popular movies and series.").lineLimit(3).frame(maxWidth: 850, alignment: .leading)
                NavigationLink { DetailView(initial: title) } label: { Label("View details", systemImage: "play.fill") }
            }.padding(60)
        }.frame(height: 480)
    }
}
