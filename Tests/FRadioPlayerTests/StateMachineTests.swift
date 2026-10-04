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

@MainActor
final class StateMachineTests: XCTestCase {

    private var fixture: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        FRadioPlayer.shared.radioURL = nil
    }

    override func tearDown() async throws {
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        try await super.tearDown()
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
        player.itemStatusDidChange(ghost, newStatus: nil)

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

    func testPlayAfterErrorRebuildsAndRecovers() throws {
        // Demo-pass find: after a fatal error, play() reattached the dead item
        // (failed items are terminal per AVFoundation), so nothing played while
        // the button showed playing. play() must rebuild from the URL instead.
        try assertPlayAfterErrorRecovers()
    }

    func testPlayAfterErrorRecoversWithCustomHeaders() throws {
        // Headers travel in the asset options, the path that broke recovery
        let player = FRadioPlayer.shared
        player.httpHeaderFields = ["User-Agent": "FRadioPlayerTests"]
        defer { player.httpHeaderFields = nil }
        try assertPlayAfterErrorRecovers()
    }

    private func assertPlayAfterErrorRecovers(file: StaticString = #filePath, line: UInt = #line) throws {
        final class StateWaiter: FRadioPlayerObserver {
            var onState: ((FRadioPlayer.State) -> Void)?
            func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
                onState?(state)
            }
        }

        let player = FRadioPlayer.shared
        player.isAutoPlay = true

        let waiter = StateWaiter()
        player.addObserver(waiter)
        defer { player.removeObserver(waiter) }

        // Phase 1: the stream is "down" (file does not exist yet)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("comeback-\(UUID().uuidString).wav")
        let errored = expectation(description: "errors while down")
        errored.assertForOverFulfill = false
        waiter.onState = { if $0 == .error { errored.fulfill() } }
        player.radioURL = tempURL
        wait(for: [errored], timeout: 10)
        XCTAssertEqual(player.playbackState, .stopped, file: file, line: line)

        // Phase 2: the "stream" comes back (file now exists)
        try Data(contentsOf: fixture).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Only readiness proves recovery: the failure path also passes
        // through other states on its way to .error
        var sawError = false
        let recovered = expectation(description: "play() rebuilds and loads")
        recovered.assertForOverFulfill = false
        waiter.onState = { state in
            if state == .error { sawError = true }
            if state == .readyToPlay { recovered.fulfill() }
        }
        player.play()
        wait(for: [recovered], timeout: 10)

        XCTAssertFalse(sawError, "retry must not fail again", file: file, line: line)
        XCTAssertNotEqual(player.state, .error, "retry must attempt a fresh load", file: file, line: line)
        XCTAssertEqual(player.playbackState, .playing, file: file, line: line)
    }

    func testFailureDoesNotFlickerLoadingFinished() {
        // A failing load goes loading -> error; observers must not see a
        // transient "loading finished" that reads as ready
        final class StateRecorder: FRadioPlayerObserver {
            var states: [FRadioPlayer.State] = []
            var onError: (() -> Void)?
            func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
                states.append(state)
                if state == .error { onError?() }
            }
        }

        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        let recorder = StateRecorder()
        player.addObserver(recorder)
        defer { player.removeObserver(recorder) }

        let errored = expectation(description: "player reports error")
        errored.assertForOverFulfill = false
        recorder.onError = { errored.fulfill() }

        player.radioURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).wav")
        wait(for: [errored], timeout: 10)

        XCTAssertEqual(recorder.states.last, .error)
        XCTAssertFalse(recorder.states.contains(.loadingFinished),
                       "states seen: \(recorder.states)")
    }

    func testStateStaysInSyncWithTimeControlOnResume() {
        // Demo-pass find: play() after stop-during-load reattaches the item
        // and re-buffers, but state stayed frozen on .loadingFinished during
        // the re-load. timeControlStatus must drive the loading vocabulary.
        let player = FRadioPlayer.shared
        player.isAutoPlay = true

        player.radioURL = fixture
        player.stop()
        XCTAssertEqual(player.state, .loadingFinished)

        player.play()

        // The player reports it is waiting: state must say loading
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertEqual(player.state, .loading,
                       "waiting while playback is intended must surface as loading")

        // The player reports audio is flowing: loading is over
        player.handleTimeControlStatus(.playing)
        XCTAssertEqual(player.state, .loadingFinished,
                       "audio flowing while state says loading is out of sync")
    }

    func testPauseCancelsPendingRecovery() {
        // A mid-playback stall starts the recovery ladder; pausing is a user
        // intent that must drop the scheduled reload, not just report paused
        let player = FRadioPlayer.shared
        let recovery = player.stallRecovery
        let originalIntervals = recovery.intervals
        let originalAttempt = recovery.onAttempt
        let originalExhausted = recovery.onExhausted
        defer {
            recovery.intervals = originalIntervals
            recovery.onAttempt = originalAttempt
            recovery.onExhausted = originalExhausted
        }

        var attempts = 0
        var exhausted = false
        recovery.intervals = [0.05, 0.05]
        recovery.onAttempt = { attempts += 1; return originalAttempt?() ?? true }
        recovery.onExhausted = { exhausted = true; originalExhausted?() }

        player.isAutoPlay = true
        player.radioURL = fixture
        XCTAssertEqual(player.playbackState, .playing)

        // Audio flowed, then the player stalls with playback intended
        player.handleTimeControlStatus(.playing)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertTrue(recovery.isActive, "a mid-playback stall must start the ladder")

        player.pause()
        XCTAssertFalse(recovery.isActive, "pause must cancel the ladder")

        settle(for: 0.3)   // well past every scheduled attempt
        XCTAssertEqual(attempts, 0, "no reload may run after pause")
        XCTAssertFalse(exhausted)
        XCTAssertEqual(player.playbackState, .paused)
        XCTAssertNotEqual(player.state, .error)
    }
}
