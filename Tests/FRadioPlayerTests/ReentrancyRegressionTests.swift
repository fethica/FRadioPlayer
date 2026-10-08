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
}
