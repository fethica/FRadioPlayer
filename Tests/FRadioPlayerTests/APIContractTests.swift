//
//  APIContractTests.swift
//  FRadioPlayerTests
//
//  Compile-time lock on the public API surface, seen exactly as a consumer
//  sees it (plain `import`, no @testable). If any reference here stops
//  compiling, a change broke the public API: either revert it or treat it
//  as a breaking change for the next major version.
//

import XCTest
import AVFoundation
import FRadioPlayer

final class APIContractTests: XCTestCase {

    // Explicit conformance: locks the exact signature of every callback.
    private final class FullObserver: FRadioPlayerObserver {
        func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {}
        func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {}
        func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {}
        func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?) {}
        func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {}
        func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval) {}
        func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval) {}
    }

    // Empty conformance: locks the existence of default implementations.
    private final class EmptyObserver: FRadioPlayerObserver {}

    // Locks the protocol requirements consumers can implement.
    private struct CustomExtractor: FRadioMetadataExtractor {
        func extract(from groups: [AVTimedMetadataGroup]) -> FRadioPlayer.Metadata? { nil }
    }

    private struct CustomArtworkAPI: FRadioArtworkAPI {
        func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping (URL?) -> Void) {
            completion(nil)
        }
    }

    func testPublicSurfaceCompiles() {
        let player = FRadioPlayer.shared

        // Readable properties, with their exact public types
        let _: Bool = player.isPlayImmediately
        let _: URL? = player.radioURL
        let _: Bool = player.isAutoPlay
        let _: Bool = player.enableArtwork
        let _: FRadioArtworkAPI = player.artworkAPI
        let _: [String: String]? = player.httpHeaderFields
        let _: FRadioMetadataExtractor = player.metadataExtractor
        let _: Float? = player.rate
        let _: Bool = player.isPlaying
        let _: Float? = player.volume
        let _: FRadioPlayer.State = player.state
        let _: FRadioPlayer.PlaybackState = player.playbackState
        let _: FRadioPlayer.Metadata? = player.currentMetadata
        let _: URL? = player.currentArtworkURL
        let _: TimeInterval = player.duration
        let _: Double = player.currentTime

        // Writable properties (no-op writes lock the setters; originals restored)
        let originalExtractor = player.metadataExtractor
        let originalArtworkAPI = player.artworkAPI
        let isPlayImmediately: Bool = player.isPlayImmediately
        let isAutoPlay: Bool = player.isAutoPlay
        let enableArtwork: Bool = player.enableArtwork
        let httpHeaderFields: [String: String]? = player.httpHeaderFields
        player.isPlayImmediately = isPlayImmediately
        player.isAutoPlay = isAutoPlay
        player.enableArtwork = enableArtwork
        player.httpHeaderFields = httpHeaderFields
        player.metadataExtractor = CustomExtractor()
        player.artworkAPI = CustomArtworkAPI()
        player.metadataExtractor = originalExtractor
        player.artworkAPI = originalArtworkAPI

        // Control methods: function references verify signatures without invoking
        let _: () -> Void = player.play
        let _: () -> Void = player.pause
        let _: () -> Void = player.stop
        let _: () -> Void = player.togglePlaying
        let _: (TimeInterval, (() -> Void)?) -> Void = player.seek(to:completion:)

        // Observation registration
        let full = FullObserver()
        let empty = EmptyObserver()
        player.addObserver(full)
        player.addObserver(empty)
        player.removeObserver(full)
        player.removeObserver(empty)
    }

    func testStateEnumIsStable() {
        // Exhaustive switch: adding/renaming a case breaks compilation here.
        let all: [FRadioPlayer.State] = [.urlNotSet, .readyToPlay, .loading, .loadingFinished, .error]
        for state in all {
            switch state {
            case .urlNotSet: XCTAssertEqual(state.description, "URL is not set")
            case .readyToPlay: XCTAssertEqual(state.description, "Ready to play")
            case .loading: XCTAssertEqual(state.description, "Loading")
            case .loadingFinished: XCTAssertEqual(state.description, "Loading finished")
            case .error: XCTAssertEqual(state.description, "Error")
            }
        }

        // Raw values are public contract for an Int-backed enum
        XCTAssertEqual(FRadioPlayer.State.urlNotSet.rawValue, 0)
        XCTAssertEqual(FRadioPlayer.State.readyToPlay.rawValue, 1)
        XCTAssertEqual(FRadioPlayer.State.loading.rawValue, 2)
        XCTAssertEqual(FRadioPlayer.State.loadingFinished.rawValue, 3)
        XCTAssertEqual(FRadioPlayer.State.error.rawValue, 4)
    }

    func testPlaybackStateEnumIsStable() {
        let all: [FRadioPlayer.PlaybackState] = [.playing, .paused, .stopped]
        for state in all {
            switch state {
            case .playing: XCTAssertEqual(state.description, "Player is playing")
            case .paused: XCTAssertEqual(state.description, "Player is paused")
            case .stopped: XCTAssertEqual(state.description, "Player is stopped")
            }
        }

        XCTAssertEqual(FRadioPlayer.PlaybackState.playing.rawValue, 0)
        XCTAssertEqual(FRadioPlayer.PlaybackState.paused.rawValue, 1)
        XCTAssertEqual(FRadioPlayer.PlaybackState.stopped.rawValue, 2)
    }

    func testMetadataTypeContract() {
        let metadata = FRadioPlayer.Metadata(artistName: "Artist", trackName: "Track", rawValue: "Artist - Track", groups: [])
        XCTAssertEqual(metadata.artistName, "Artist")
        XCTAssertEqual(metadata.trackName, "Track")
        XCTAssertEqual(metadata.rawValue, "Artist - Track")
        XCTAssertTrue(metadata.groups.isEmpty)
        XCTAssertFalse(metadata.isEmpty)

        // isEmpty looks only at artist and track, not rawValue
        let empty = FRadioPlayer.Metadata(artistName: nil, trackName: nil, rawValue: "raw", groups: [])
        XCTAssertTrue(empty.isEmpty)
    }
}
