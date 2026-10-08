//
//  DiscardRebuildReentrancyTests.swift
//  FRadioPlayerTests
//
//  The rebuild that play() runs after stop(discardingItem: true) publishes
//  `.loading` before it builds. A host acting from that callback must win:
//  the outer rebuild may neither construct its item nor touch the player a
//  nested call set up (re-review finding R01).
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class DiscardRebuildReentrancyTests: XCTestCase {

    /// Runs its action once, from the first `.loading` callback
    private final class ActOnLoading: FRadioPlayerObserver {
        var action: ((FRadioPlayer) -> Void)?
        var playbackStates: [FRadioPlayer.PlaybackState] = []
        var items: [URL?] = []

        func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
            guard state == .loading, let action = action else { return }
            self.action = nil
            action(player)
        }
        func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {
            playbackStates.append(state)
        }
        func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
            items.append(url)
        }
    }

    private var fixture: URL!
    private var other: URL!
    private var recorder: ActOnLoading?

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        other = try TestAudio.silentWAV(seconds: 1)
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        if let recorder = recorder { player.removeObserver(recorder) }
        recorder = nil
        player.radioURL = nil
        player.isAutoPlay = true
        try? FileManager.default.removeItem(at: other)
        try await super.tearDown()
    }

    /// Loads the fixture, discards its item, then arms `action` for the
    /// `.loading` callback of the next play()
    private func discardThenArm(_ action: @escaping (FRadioPlayer) -> Void) -> ActOnLoading {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        player.stop(discardingItem: true)
        let recorder = ActOnLoading()
        recorder.action = action
        player.addObserver(recorder)
        self.recorder = recorder
        return recorder
    }

    private func assetURL(_ item: AVPlayerItem?) -> URL? {
        (item?.asset as? AVURLAsset)?.url
    }

    func testURLChangeFromLoadingOfDiscardRebuildWins() throws {
        let player = FRadioPlayer.shared
        let other = self.other!
        let recorder = discardThenArm { $0.radioURL = other }
        let generation = player.itemGeneration

        player.play()

        XCTAssertEqual(player.radioURL, other)
        let item = try XCTUnwrap(player.playerItem)
        XCTAssertEqual(assetURL(item), other, "the outer rebuild must not attach the old URL's item")
        XCTAssertIdentical(player.attachedItem, item)
        XCTAssertEqual(player.itemGeneration, generation + 1, "the superseded rebuild never constructs an item")
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertEqual(recorder.items, [other])
        XCTAssertEqual(recorder.playbackStates, [.playing], "no replacement pause/play churn")
    }

    func testDiscardingStopFromLoadingOfDiscardRebuildSticks() throws {
        let player = FRadioPlayer.shared
        let recorder = discardThenArm { $0.stop(discardingItem: true) }
        let generation = player.itemGeneration

        player.play()

        XCTAssertEqual(player.playbackState, .stopped, "the STOP issued from .loading wins")
        XCTAssertFalse(recorder.playbackStates.contains(.playing))
        XCTAssertNil(player.playerItem)
        XCTAssertNil(player.attachedItem)
        XCTAssertEqual(player.itemGeneration, generation, "no item is constructed after the STOP")

        // The next play() still connects fresh
        player.play()
        XCTAssertEqual(player.itemGeneration, generation + 1)
        XCTAssertIdentical(player.attachedItem, player.playerItem)
        XCTAssertEqual(player.playbackState, .playing)
    }

    func testDiscardAndPlayFromLoadingOfDiscardRebuildBuildsOneItem() throws {
        let player = FRadioPlayer.shared
        let recorder = discardThenArm { player in
            player.stop(discardingItem: true)
            player.play()
        }
        let generation = player.itemGeneration

        player.play()

        XCTAssertEqual(player.itemGeneration, generation + 1, "only the nested rebuild constructs an item")
        let item = try XCTUnwrap(player.playerItem)
        XCTAssertIdentical(player.attachedItem, item)
        XCTAssertEqual(assetURL(item), fixture)
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertEqual(recorder.playbackStates, [.playing], "the outer call does not act on the nested player")
    }
}
