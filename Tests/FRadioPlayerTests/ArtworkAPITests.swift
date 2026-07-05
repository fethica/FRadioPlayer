//
//  ArtworkAPITests.swift
//  FRadioPlayerTests
//
//  Tests for the iTunes artwork API using a stubbed URLProtocol.
//  No network involved: iTunesAPI accepts an injected URLSession.
//

import XCTest
import FRadioPlayer

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequestURL: URL?
    nonisolated(unsafe) static var responseData: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequestURL = request.url
        if let url = request.url, let data = Self.responseData {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ArtworkAPITests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.lastRequestURL = nil
        StubURLProtocol.responseData = nil
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func metadata(raw: String?) -> FRadioPlayer.Metadata {
        FRadioPlayer.Metadata(artistName: raw, trackName: raw, rawValue: raw, groups: [])
    }

    func testRequestTargetsITunesSearchAPI() throws {
        StubURLProtocol.responseData = Data(#"{"results":[]}"#.utf8)
        let api = iTunesAPI(artworkSize: 300, session: stubbedSession())

        let done = expectation(description: "completion")
        api.getArtwork(for: metadata(raw: "Artist - Song")) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)

        let url = try XCTUnwrap(StubURLProtocol.lastRequestURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "itunes.apple.com")
        XCTAssertEqual(components.path, "/search")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["term"], "Artist - Song")
        XCTAssertEqual(query["entity"], "song")
    }

    func testArtworkSizeIsSubstituted() {
        StubURLProtocol.responseData = Data(#"{"results":[{"artworkUrl100":"https://example.com/img/100x100bb.jpg"}]}"#.utf8)
        let api = iTunesAPI(artworkSize: 300, session: stubbedSession())

        let done = expectation(description: "completion")
        var result: URL?
        api.getArtwork(for: metadata(raw: "Artist - Song")) { url in
            result = url
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.absoluteString, "https://example.com/img/300x300bb.jpg")
    }

    func testSize100KeepsOriginalURL() {
        StubURLProtocol.responseData = Data(#"{"results":[{"artworkUrl100":"https://example.com/img/100x100bb.jpg"}]}"#.utf8)
        let api = iTunesAPI(artworkSize: 100, session: stubbedSession())

        let done = expectation(description: "completion")
        var result: URL?
        api.getArtwork(for: metadata(raw: "x")) { url in
            result = url
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.absoluteString, "https://example.com/img/100x100bb.jpg")
    }

    func testEmptyMetadataCompletesNilWithoutRequest() {
        let api = iTunesAPI(artworkSize: 300, session: stubbedSession())

        let done = expectation(description: "completion")
        var result: URL? = URL(string: "https://sentinel.invalid")
        api.getArtwork(for: metadata(raw: nil)) { url in
            result = url
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertNil(result)
        XCTAssertNil(StubURLProtocol.lastRequestURL, "empty metadata must not hit the network")
    }

    func testMalformedResponseCompletesNil() {
        StubURLProtocol.responseData = Data("not json".utf8)
        let api = iTunesAPI(artworkSize: 300, session: stubbedSession())

        let done = expectation(description: "completion")
        var result: URL? = URL(string: "https://sentinel.invalid")
        api.getArtwork(for: metadata(raw: "Artist - Song")) { url in
            result = url
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertNil(result)
    }
}
