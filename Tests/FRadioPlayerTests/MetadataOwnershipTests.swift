//
//  MetadataOwnershipTests.swift
//  FRadioPlayerTests
//
//  Timed metadata already queued on the main queue when an item is
//  discarded or replaced must not repopulate the cleared metadata or start
//  an artwork lookup (re-review finding R03). Delivery is driven through the
//  real delegate entry point with the output captured before the discard.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class MetadataOwnershipTests: XCTestCase {

    /// Records every lookup through an expectation, resolves nothing
    private struct ExpectingArtworkAPI: FRadioArtworkAPI {
        let lookup: XCTestExpectation
        func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping @Sendable (URL?) -> Void) {
            lookup.fulfill()
            completion(nil)
        }
    }

    private final class MetadataRecorder: FRadioPlayerObserver {
        var values: [String?] = []
        func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?) {
            values.append(metadata?.rawValue)
        }
    }

    private var fixture: URL!
    private var originalArtworkAPI: FRadioArtworkAPI?
    private var recorder: MetadataRecorder?

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        let player = FRadioPlayer.shared
        player.radioURL = nil
        player.isAutoPlay = true
        originalArtworkAPI = player.artworkAPI
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        if let recorder = recorder { player.removeObserver(recorder) }
        recorder = nil
        player.radioURL = nil
        if let api = originalArtworkAPI { player.artworkAPI = api }
        player.enableArtwork = true
        try await super.tearDown()
    }

    private func groups(_ value: String) -> [AVTimedMetadataGroup] {
        let item = AVMutableMetadataItem()
        item.value = value as NSString
        return [AVTimedMetadataGroup(items: [item], timeRange: CMTimeRange(start: .zero, duration: .zero))]
    }

    /// Loads the fixture and returns the output feeding its item, with an
    /// artwork provider that fails the test if it is asked
    private func loadWithForbiddenArtwork() -> AVPlayerItemMetadataOutput {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        let noLookup = expectation(description: "no artwork lookup for stale metadata")
        noLookup.isInverted = true
        player.artworkAPI = ExpectingArtworkAPI(lookup: noLookup)
        player.enableArtwork = true
        let recorder = MetadataRecorder()
        player.addObserver(recorder)
        self.recorder = recorder
        return player.metadataOutput
    }

    func testQueuedMetadataAfterDiscardIsDropped() throws {
        let player = FRadioPlayer.shared
        let oldOutput = loadWithForbiddenArtwork()

        player.stop(discardingItem: true)
        player.metadataOutput(oldOutput, didOutputTimedMetadataGroups: groups("Old - Track"), from: nil)

        XCTAssertNil(player.currentMetadata, "the discarded item's metadata stays cleared")
        XCTAssertEqual(recorder?.values.compactMap { $0 }, [], "no metadata callback for the old item")
        waitForExpectations(timeout: 0.3)
    }

    func testQueuedMetadataAfterDiscardAndReplayIsDropped() throws {
        let player = FRadioPlayer.shared
        let oldOutput = loadWithForbiddenArtwork()

        player.stop(discardingItem: true)
        player.play()
        XCTAssertNotNil(player.playerItem)
        player.metadataOutput(oldOutput, didOutputTimedMetadataGroups: groups("Old - Track"), from: nil)

        XCTAssertNil(player.currentMetadata, "the old output cannot describe the fresh item")
        XCTAssertEqual(recorder?.values.compactMap { $0 }, [])
        waitForExpectations(timeout: 0.3)
    }

    func testFreshItemsOutputStillDelivers() throws {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        player.stop(discardingItem: true)
        player.play()

        let lookup = expectation(description: "artwork lookup for the fresh item")
        player.artworkAPI = ExpectingArtworkAPI(lookup: lookup)
        player.enableArtwork = true
        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: groups("New - Track"), from: nil)

        XCTAssertEqual(player.currentMetadata?.rawValue, "New - Track")
        waitForExpectations(timeout: 1)
    }
}
