//
//  StateMachineTests.swift
//  FRadioPlayerTests
//
//  Regression coverage for playback state correctness (issue #12 family):
//  a stop must stick, even when issued while the item is still loading.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

final class StateMachineTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        FRadioPlayer.shared.radioURL = nil
    }

    override func tearDown() {
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        super.tearDown()
    }

    func testStopDuringLoadingSticks() {
        let player = FRadioPlayer.shared
        player.isAutoPlay = true

        player.radioURL = fixture   // autoplay kicks in, item still loading
        player.stop()               // user changes their mind immediately

        XCTAssertEqual(player.playbackState, .stopped)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.state, .loadingFinished,
                       "stopping an in-flight load must end the loading lifecycle, not freeze it")

        // Readiness lands asynchronously: it must NOT resurrect playback
        let settled = expectation(description: "async readiness settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertEqual(player.playbackState, .stopped,
                       "readiness arriving after stop() must not restart playback")
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.rate ?? 0, 0, "AVPlayer must not be advancing after stop")
        XCTAssertNotEqual(player.state, .loading,
                          "state must never sit on loading after a stop")
    }

    func testDetachedItemChurnCannotResurrectLoading() {
        // Demo-pass repro: on real streams, the item detached by stop() keeps
        // churning its buffer properties asynchronously; those KVO signals
        // must not flip state back to .loading (the post-stop "blink").
        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        player.radioURL = fixture
        player.stop()
        XCTAssertEqual(player.state, .loadingFinished)

        // Simulate the detached item's async churn directly on the handlers
        let ghost = AVPlayerItem(url: fixture)
        player.itemBufferEmptyDidChange(ghost)
        player.itemKeepUpDidChange(ghost)
        player.itemDurationDidChange(ghost)
        player.itemStatusDidChange(ghost, change: nil)

        XCTAssertEqual(player.state, .loadingFinished,
                       "detached-item KVO must not drive the loading vocabulary")
        XCTAssertEqual(player.playbackState, .stopped)
    }

    func testDeadStreamStopsPlaybackAlongsideErrorState() {
        // Demo-pass find: a stream that fails at connect time set state to
        // .error but left playbackState on .playing, so play buttons lied.
        final class ErrorWaiter: FRadioPlayerObserver {
            var onError: (() -> Void)?
            func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
                if state == .error { onError?() }
            }
        }

        let player = FRadioPlayer.shared
        player.isAutoPlay = true

        let waiter = ErrorWaiter()
        player.addObserver(waiter)
        defer { player.removeObserver(waiter) }

        let errored = expectation(description: "player reports error")
        errored.assertForOverFulfill = false
        waiter.onError = { errored.fulfill() }

        // A nonexistent local file fails the item deterministically, no network
        player.radioURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).wav")
        wait(for: [errored], timeout: 10)

        XCTAssertEqual(player.state, .error)
        XCTAssertEqual(player.playbackState, .stopped,
                       "a fatal stream error must stop playback, not leave the button on playing")
        XCTAssertFalse(player.isPlaying)
    }

    func testPauseCancelsPendingRecovery() {
        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        player.radioURL = fixture

        // Whatever the loading state, pausing is a user intent that must
        // both hold and report correctly.
        player.pause()
        XCTAssertEqual(player.playbackState, .paused)
        XCTAssertFalse(player.isPlaying)
    }
}
