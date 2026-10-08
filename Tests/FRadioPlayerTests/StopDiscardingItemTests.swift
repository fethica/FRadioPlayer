//
//  StopDiscardingItemTests.swift
//  FRadioPlayerTests
//
//  A live STOP must be able to drop the item so the next play() for the
//  same URL connects fresh (ledger R06, AU-013/AU-014 prerequisite).
//  `stop(discardingItem: false)` is exactly `stop()`.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class StopDiscardingItemTests: XCTestCase {

    private struct FixedExtractor: FRadioMetadataExtractor {
        func extract(from groups: [AVTimedMetadataGroup]) -> FRadioPlayer.Metadata? {
            FRadioPlayer.Metadata(artistName: "Artist", trackName: "Track", rawValue: "Artist - Track", groups: [])
        }
    }

    private var fixture: URL!
    private var file: URL?
    private var originalExtractor: FRadioMetadataExtractor?

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        FRadioPlayer.shared.radioURL = nil
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.radioURL = nil
        player.isAutoPlay = true
        player.enableArtwork = true
        player.playerItemConfigurator = nil
        if let extractor = originalExtractor { player.metadataExtractor = extractor }
        originalExtractor = nil
        if let file = file { try? FileManager.default.removeItem(at: file) }
        file = nil
        try await super.tearDown()
    }

    /// Delivers fake timed metadata through the real delegate entry point
    private func injectMetadata(_ player: FRadioPlayer) {
        originalExtractor = player.metadataExtractor
        player.enableArtwork = false
        player.metadataExtractor = FixedExtractor()
        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: [], from: nil)
        XCTAssertNotNil(player.currentMetadata)
    }

    func testDiscardingFalseIsPlainStop() throws {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        let item = try XCTUnwrap(player.playerItem)
        let generation = player.itemGeneration

        player.stop(discardingItem: false)
        XCTAssertEqual(player.playbackState, .stopped)
        XCTAssertEqual(player.state, .loadingFinished)
        XCTAssertIdentical(player.playerItem, item)

        player.play()
        XCTAssertIdentical(player.attachedItem, item, "the kept item is reattached")
        XCTAssertEqual(player.itemGeneration, generation)
    }

    func testDiscardingDuringLoadDropsItemAndPlayBuildsFreshOne() throws {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        let old = try XCTUnwrap(player.playerItem)
        let generation = player.itemGeneration

        player.stop(discardingItem: true)
        XCTAssertEqual(player.playbackState, .stopped)
        XCTAssertEqual(player.state, .loadingFinished)
        XCTAssertNil(player.playerItem)
        XCTAssertNil(player.attachedItem)
        XCTAssertEqual(player.itemGeneration, generation, "no item is created until play()")
        XCTAssertEqual(player.radioURL, fixture, "the URL is kept")

        var configured: [AVPlayerItem] = []
        player.playerItemConfigurator = { configured.append($0) }
        player.play()

        let fresh = try XCTUnwrap(player.playerItem)
        XCTAssertFalse(fresh === old, "play() after a discarding stop builds a new item")
        XCTAssertIdentical(player.attachedItem, fresh)
        XCTAssertEqual(player.itemGeneration, generation + 1)
        XCTAssertEqual(configured.count, 1)
        XCTAssertIdentical(configured.first, fresh)
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertTrue(waitUntil { player.state == .readyToPlay || player.state == .loadingFinished })
    }

    func testDiscardingOnFileClearsMetadataAndDuration() throws {
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared
        injectMetadata(player)

        // 0.4.0 file branch keeps the metadata on a plain stop
        player.stop()
        XCTAssertNotNil(player.currentMetadata)
        player.play()

        player.stop(discardingItem: true)
        XCTAssertNil(player.currentMetadata)
        XCTAssertNil(player.currentArtworkURL)
        XCTAssertNil(player.playerItem)
        XCTAssertNil(player.attachedItem)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(player.currentTime, 0)

        player.play()
        XCTAssertNotNil(player.playerItem)
        XCTAssertTrue(waitUntil { player.duration > 0 }, "the fresh item loads the same file")
    }

    func testDiscardedItemSignalsAreIgnored() throws {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        let old = try XCTUnwrap(player.playerItem)
        player.stop(discardingItem: true)

        player.bufferEmptyDidChange(old, isEmpty: true)
        player.itemStatusDidChange(old, newStatus: .failed)
        XCTAssertEqual(player.state, .loadingFinished)
        XCTAssertNil(player.lastFailure)
    }

    func testDiscardingWithoutURLIsHarmless() {
        let player = FRadioPlayer.shared
        player.stop(discardingItem: true)
        player.play()
        XCTAssertEqual(player.state, .urlNotSet)
        XCTAssertNil(player.playerItem)
    }

    func testPlayInsideConfiguratorDoesNotRecurse() {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        player.stop(discardingItem: true)

        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            player.play()   // misuse: must not rebuild again from inside
        }
        player.play()
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(player.playerItem)
    }
}
