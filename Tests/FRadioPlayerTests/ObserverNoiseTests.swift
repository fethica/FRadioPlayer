//
//  ObserverNoiseTests.swift
//  FRadioPlayerTests
//
//  Observers must receive exactly one callback per actual change.
//  These tests pin the intended counts; the double-fires they catch
//  came from the reset path notifying alongside the change itself.
//

import XCTest
import FRadioPlayer

final class ObserverNoiseTests: XCTestCase {

    private final class Recorder: FRadioPlayerObserver {
        var itemChanges: [URL?] = []
        var artworkChanges: [URL?] = []
        var playbackStates: [FRadioPlayer.PlaybackState] = []

        func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
            itemChanges.append(url)
        }
        func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {
            artworkChanges.append(artworkURL)
        }
        func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {
            playbackStates.append(state)
        }
    }

    private var recorder: Recorder!
    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        // Normalize the shared player BEFORE attaching the recorder
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = false
        recorder = Recorder()
        FRadioPlayer.shared.addObserver(recorder)
    }

    override func tearDown() {
        FRadioPlayer.shared.removeObserver(recorder)
        recorder = nil
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        super.tearDown()
    }

    func testSettingURLNotifiesItemChangeExactlyOnce() {
        FRadioPlayer.shared.radioURL = fixture
        XCTAssertEqual(recorder.itemChanges, [fixture],
                       "one radioURL set must produce exactly one itemDidChange")
    }

    func testSwitchingURLsNotifiesItemChangeExactlyOnce() {
        // The station-switch case: a previous item exists, so the reset pass
        // used to notify alongside the new-item pass (the double call).
        FRadioPlayer.shared.radioURL = fixture
        recorder.itemChanges.removeAll()

        FRadioPlayer.shared.radioURL = fixture
        XCTAssertEqual(recorder.itemChanges, [fixture],
                       "switching from one URL to another must produce exactly one itemDidChange")
    }

    func testClearingURLNotifiesItemChangeExactlyOnce() {
        FRadioPlayer.shared.radioURL = fixture
        recorder.itemChanges.removeAll()

        FRadioPlayer.shared.radioURL = nil
        XCTAssertEqual(recorder.itemChanges, [nil],
                       "clearing radioURL must produce exactly one itemDidChange(nil)")
    }

    func testArtworkNeverNotifiesTheSameValueTwiceInARow() {
        FRadioPlayer.shared.radioURL = fixture
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.radioURL = fixture

        for (a, b) in zip(recorder.artworkChanges, recorder.artworkChanges.dropFirst()) {
            XCTAssertNotEqual(a, b, "artworkDidChange fired twice in a row with the same value")
        }
    }

    func testURLChangesWhileIdleEmitNoPlaybackNoise() {
        // Never played: no playback-state event should fire at all,
        // in particular not the spurious .paused from the teardown path.
        FRadioPlayer.shared.radioURL = fixture
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.radioURL = fixture

        XCTAssertEqual(recorder.playbackStates, [],
                       "idle URL changes must not emit playback state changes")
        XCTAssertEqual(FRadioPlayer.shared.playbackState, .stopped)
    }
}
