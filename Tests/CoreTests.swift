import XCTest
@testable import WatchlyCore

final class CoreTests: XCTestCase {
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
