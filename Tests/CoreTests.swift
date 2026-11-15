import XCTest
@testable import WatchlyCore

final class CoreTests: XCTestCase {
    func testDirectProviderURLIsPreferredOverTorrentHash() {
        let source = StreamSource(infoHash: String(repeating: "a", count: 40), url: "https://example.com/video.mp4")
        XCTAssertEqual(source.location, "https://example.com/video.mp4")
    }
    func testPendingReadEventuallyReturnsBytes() async throws {
        var attempts = 0
        let bytes = try await StreamReadLoop.read(timeout: 1, interval: 1_000) {
            attempts += 1
            return attempts < 3 ? .pending : .bytes(Data([1, 2, 3]))
        }
        XCTAssertEqual(bytes, Data([1, 2, 3]))
        XCTAssertEqual(attempts, 3)
    }
    func testStalledReadTimesOut() async {
        do {
            _ = try await StreamReadLoop.read(timeout: 0, interval: 1_000) { .pending }
            XCTFail("A stalled read must time out")
        } catch { XCTAssertTrue(error is StreamReadError) }
    }
    func testCancelledStorageWaitStopsPromptly() async {
        let task = Task { try await StreamReadLoop.read(interval: 1_000_000) { .storageLimited } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled wait must not continue") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testStorageWaitCanResumeWithoutAFalseTimeout() async throws {
        var attempts = 0
        let bytes = try await StreamReadLoop.read(timeout: 0.1, interval: 1_000) {
            attempts += 1
            if attempts == 1 { try await Task.sleep(nanoseconds: 150_000_000); return .storageLimited }
            return .bytes(Data([4]))
        }
        XCTAssertEqual(bytes, Data([4]))
    }
    func testDiscoverSortsMissingMetadataLastAndPreservesTies() {
        let items = [MediaTitle(id: "1", type: "movie", name: "Zebra"),
                     MediaTitle(id: "2", type: "movie", name: "Alpha", releaseInfo: "2024–", imdbRating: "8.5"),
                     MediaTitle(id: "3", type: "movie", name: "Beta", releaseInfo: "2024", imdbRating: "8.5")]
        XCTAssertEqual(DiscoverSelection(sort: .catalogue).ordered(items).map(\.id), ["1", "2", "3"])
        for sort in [DiscoverSort.title, .newest, .rating] {
            XCTAssertEqual(DiscoverSelection(sort: sort).ordered(items).map(\.id), ["2", "3", "1"])
        }
    }
    func testSkipMarkersRequireValidBoundsAndRespectAbsence() throws {
        let data = Data(#"{"intro":{"start_ms":10000,"end_ms":30000},"outro":{"start_sec":90,"end_sec":100}}"#.utf8)
        let segments = try JSONDecoder().decode(SkipSegments.self, from: data)
        XCTAssertNil(segments.intro(at: 9, duration: 120))
        XCTAssertEqual(segments.intro(at: 10, duration: 120)?.end, 30)
        XCTAssertNil(segments.intro(at: 30, duration: 120))
        XCTAssertNil(segments.outro(at: 95, duration: 99))
        XCTAssertEqual(segments.outro(at: 95, duration: 120)?.end, 100)
        let missing = try JSONDecoder().decode(SkipSegment.self, from: Data(#"{"end_sec":30}"#.utf8))
        XCTAssertFalse(missing.isAvailable(at: 20, duration: 100))
        var absent = segments; absent.no_intro = true
        XCTAssertNil(absent.intro(at: 15, duration: 120))
    }
    func testCreditsSkipPreservesReportedPostCreditsScene() throws {
        let segments = try JSONDecoder().decode(SkipSegments.self, from: Data(#"{"outro":{"start_sec":90,"end_sec":120},"post_credits":{"start_sec":110,"end_sec":115}}"#.utf8))
        let outro = try XCTUnwrap(segments.outro(at: 95, duration: 130))
        XCTAssertEqual(segments.outroDestination(outro), 110)
        XCTAssertNil(segments.outro(at: 110, duration: 130))
    }
    func testProviderEpisodeNameAndRoundTrip() throws {
        let data = Data(#"{"id":"tt1:1:2","season":1,"episode":2,"name":"Pilot","description":"Overview"}"#.utf8)
        let episode = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertEqual(episode.title, "Pilot")
        XCTAssertEqual(episode.overview, "Overview")
        XCTAssertEqual(try JSONDecoder().decode(Episode.self, from: JSONEncoder().encode(episode)), episode)
    }
    func testRanges() throws {
        XCTAssertEqual(try ByteRange.parse(nil, size: 100), ByteRange(lower: 0, upper: 99))
        XCTAssertEqual(try ByteRange.parse("bytes=20-", size: 100), ByteRange(lower: 20, upper: 99))
        XCTAssertEqual(try ByteRange.parse("bytes=20-200", size: 100), ByteRange(lower: 20, upper: 99))
        XCTAssertEqual(try ByteRange.parse("bytes=-20", size: 100), ByteRange(lower: 80, upper: 99))
        XCTAssertEqual(try ByteRange.parse("bytes=-200", size: 100), ByteRange(lower: 0, upper: 99))
        for value in ["bytes=100-", "bytes=5-2", "bytes=-0", "bytes=0-1,3-4", "bytes=a-", "bytes=--1"] {
            XCTAssertThrowsError(try ByteRange.parse(value, size: 100), value)
        }
        XCTAssertThrowsError(try ByteRange.parse(nil, size: 0))
    }
    func testEpisodeSelectionDoesNotConfuseEpisodePrefixes() {
        let ep = Episode(id: "tt1:1:2", season: 1, episode: 2)
        XCTAssertTrue(TorrentFile(id: 0, name: "Show.S01E02.mkv", size: 1).matches(ep))
        XCTAssertTrue(TorrentFile(id: 0, name: "Show.1x02.mkv", size: 1).matches(ep))
        XCTAssertFalse(TorrentFile(id: 0, name: "Show.S01E20.mkv", size: 1).matches(ep))
        XCTAssertFalse(TorrentFile(id: 0, name: "Show.S02E02.mkv", size: 1).matches(ep))
    }
    func testMagnetEncodingAndFileIdentity() throws {
        let hash = String(repeating: "a", count: 40)
        let source = StreamSource(title: "A & B + C", infoHash: hash, fileIdx: 2)
        let url = try XCTUnwrap(URLComponents(string: try XCTUnwrap(source.magnet)))
        XCTAssertEqual(url.queryItems?.first(where: { $0.name == "dn" })?.value, "A & B + C")
        XCTAssertNotEqual(source.id, StreamSource(infoHash: hash, fileIdx: 3).id)
        XCTAssertNil(StreamSource(infoHash: "invalid").magnet)
    }
}
