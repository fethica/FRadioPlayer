//
//  ReentrancyRegressionTests.swift
//  FRadioPlayerTests
//
//  Observers and the item configurator may call back into the player
//  synchronously. These pin what 0.4.0 did for existing callbacks and what
//  the 0.5.0 seams must do when a host acts from inside them (review
//  findings S26-01, S26-05, S26-06).
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class ReentrancyRegressionTests: XCTestCase {

    /// Calls play() from the `.loading` state callback, the existing-API
    /// trace from the review, and records what observers see
    private final class PlayOnLoading: FRadioPlayerObserver {
        var playbackStates: [FRadioPlayer.PlaybackState] = []
        var loadingCalls = 0
        var armed = true

        func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
            guard armed, state == .loading else { return }
            loadingCalls += 1
            player.play()
        }
        func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {
            playbackStates.append(state)
        }
    }

    private var fixture: URL!
    private var observers: [FRadioPlayerObserver] = []

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        FRadioPlayer.shared.radioURL = nil
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        observers.forEach { player.removeObserver($0) }
        observers.removeAll()
        player.playerItemConfigurator = nil
        player.radioURL = nil
        player.isAutoPlay = true
        try await super.tearDown()
    }

    private func observe<T: FRadioPlayerObserver>(_ observer: T) -> T {
        observers.append(observer)
        FRadioPlayer.shared.addObserver(observer)
        return observer
    }

    // MARK: - S26-01: play() from the .loading callback

    /// 0.4.0: the nested play() finds no AVPlayer yet and returns; the outer
    /// setup creates one item and autoplays it. One `.playing`, one item.
    func testPlayFromLoadingOnFirstLoadBuildsOneItem() throws {
        let player = FRadioPlayer.shared
        let recorder = observe(PlayOnLoading())
        let generation = player.itemGeneration

        player.radioURL = fixture
        recorder.armed = false

        XCTAssertEqual(recorder.loadingCalls, 1)
        XCTAssertEqual(recorder.playbackStates, [.playing], "no nested build, no paused/playing churn")
        XCTAssertEqual(player.itemGeneration, generation + 1, "exactly one item is created")
        XCTAssertIdentical(player.attachedItem, player.playerItem)
    }

    /// The same callback after a discarding stop: play() rebuilds once,
    /// and the play() nested in `.loading` must not rebuild again.
    func testPlayFromLoadingAfterDiscardingStopBuildsOneItem() throws {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        player.stop(discardingItem: true)
        let generation = player.itemGeneration

        let recorder = observe(PlayOnLoading())
        player.play()
        recorder.armed = false

        XCTAssertEqual(recorder.loadingCalls, 1)
        XCTAssertEqual(recorder.playbackStates, [.playing])
        XCTAssertEqual(player.itemGeneration, generation + 1, "exactly one fresh item")
        let item = try XCTUnwrap(player.playerItem)
        XCTAssertIdentical(player.attachedItem, item)
        XCTAssertEqual(player.playbackState, .playing)
    }

    // MARK: - S26-05: controls issued from inside the configurator

    private final class ItemRecorder: FRadioPlayerObserver {
        var items: [URL?] = []
        var playbackStates: [FRadioPlayer.PlaybackState] = []
        func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
            items.append(url)
        }
        func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {
            playbackStates.append(state)
        }
    }

    private func assetURL(_ item: AVPlayerItem?) -> URL? {
        (item?.asset as? AVURLAsset)?.url
    }

    func testStopDiscardingInConfiguratorOnURLChangeSticks() throws {
        let player = FRadioPlayer.shared
        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            if calls == 1 { player.stop(discardingItem: true) }
        }
        let recorder = observe(ItemRecorder())

        player.radioURL = fixture
        XCTAssertEqual(player.playbackState, .stopped, "the STOP issued in the hook wins")
        XCTAssertFalse(recorder.playbackStates.contains(.playing), "no autoplay of the abandoned item")
        XCTAssertNil(player.playerItem)
        XCTAssertNil(player.attachedItem)
        XCTAssertEqual(player.radioURL, fixture)
        XCTAssertEqual(recorder.items, [fixture], "the URL change itself is still reported once")

        // The next play() connects fresh
        let generation = player.itemGeneration
        player.play()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(player.itemGeneration, generation + 1)
        XCTAssertNotNil(player.playerItem)
        XCTAssertIdentical(player.attachedItem, player.playerItem)
        XCTAssertEqual(player.playbackState, .playing)
    }

    func testStopInConfiguratorOnPlayAfterDiscardSticks() throws {
        let player = FRadioPlayer.shared
        player.radioURL = fixture
        player.stop(discardingItem: true)

        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            if calls == 1 { player.stop() }
        }
        player.play()
        XCTAssertEqual(player.playbackState, .stopped, "a plain stop in the hook also wins")
        XCTAssertNil(player.attachedItem)
        XCTAssertNil(player.playerItem, "the abandoned item is never kept")

        player.play()
        XCTAssertEqual(calls, 2, "and the next play() builds again")
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertIdentical(player.attachedItem, player.playerItem)
    }

    func testURLSwitchInConfiguratorKeepsTheNewURLsItem() throws {
        let player = FRadioPlayer.shared
        let other = try TestAudio.silentWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: other) }

        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            if calls == 1 { player.radioURL = other }
        }
        let recorder = observe(ItemRecorder())

        player.radioURL = fixture
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(player.radioURL, other)
        let item = try XCTUnwrap(player.playerItem)
        XCTAssertEqual(assetURL(item), other, "the outer setup must not overwrite the newer item")
        XCTAssertIdentical(player.attachedItem, item)
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertEqual(recorder.items.last, other, "observers end on the URL actually in use")
        XCTAssertFalse(recorder.items.contains(fixture), "the superseded URL never became an item")
    }
}
