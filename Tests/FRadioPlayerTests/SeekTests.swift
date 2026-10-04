//
//  SeekTests.swift
//  FRadioPlayerTests
//
//  The seek(to:completion:) contract: the completion runs exactly once, on
//  the main actor, after the call returns, on every path. Seeking never
//  resumes a player that was not playing, and a pause issued while the
//  seek is in flight wins.
//

import XCTest
@testable import FRadioPlayer

@MainActor
final class SeekTests: XCTestCase {

    private var files: [URL] = []

    override func tearDown() async throws {
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        files = []
        try await super.tearDown()
    }

    /// Seeks and waits for the completion, failing on a second call.
    private func seekAndWait(to seconds: TimeInterval, afterCall: () -> Void = {}) {
        let player = FRadioPlayer.shared
        let done = expectation(description: "seek completion")
        var calls = 0
        var calledSynchronously = true

        player.seek(to: seconds) {
            calls += 1
            XCTAssertTrue(Thread.isMainThread, "completion must run on the main actor")
            XCTAssertFalse(calledSynchronously, "completion must run after seek returns")
            done.fulfill()
        }
        calledSynchronously = false
        afterCall()

        wait(for: [done], timeout: 5)
        settle(for: 0.3)
        XCTAssertEqual(calls, 1, "completion must be called exactly once")
    }

    // MARK: - Completion on every path

    func testCompletionRunsWithoutPlayer() {
        FRadioPlayer.shared.radioURL = nil
        seekAndWait(to: 10)
        XCTAssertEqual(FRadioPlayer.shared.playbackState, .stopped)
    }

    func testCompletionRunsForLiveStream() throws {
        // Before the item reports a duration, the player treats it as live
        let player = FRadioPlayer.shared
        player.isAutoPlay = false
        let url = try TestAudio.silentWAV(seconds: 5)
        files.append(url)
        player.radioURL = url
        XCTAssertEqual(player.duration, 0)

        seekAndWait(to: 1)
        XCTAssertNotEqual(player.playbackState, .playing, "a seek on a live stream must not start playback")
    }

    func testSupersededSeekStillCompletesOnce() throws {
        files.append(try loadSeekableFile(autoPlay: true))
        let player = FRadioPlayer.shared

        let first = expectation(description: "first completion")
        let second = expectation(description: "second completion")
        player.seek(to: 1) { first.fulfill() }
        player.seek(to: 3) { second.fulfill() }
        wait(for: [first, second], timeout: 5)
        settle(for: 0.3)   // over-fulfilment would fail the expectations

        XCTAssertEqual(player.playbackState, .playing)
    }

    // MARK: - Playback intent

    func testSeekWhilePlayingKeepsPlaying() throws {
        files.append(try loadSeekableFile(autoPlay: true))
        XCTAssertEqual(FRadioPlayer.shared.playbackState, .playing)

        seekAndWait(to: 2)
        XCTAssertEqual(FRadioPlayer.shared.playbackState, .playing)
    }

    func testSeekWhilePausedStaysPaused() throws {
        files.append(try loadSeekableFile(autoPlay: true))
        let player = FRadioPlayer.shared
        player.pause()

        seekAndWait(to: 2)
        XCTAssertEqual(player.playbackState, .paused, "seeking must not resume a paused player")
        XCTAssertEqual(player.rate ?? 0, 0)
    }

    func testSeekWhileStoppedStaysStopped() throws {
        files.append(try loadSeekableFile(autoPlay: true))
        let player = FRadioPlayer.shared
        player.stop()

        seekAndWait(to: 2)
        XCTAssertEqual(player.playbackState, .stopped, "seeking must not resume a stopped player")
        XCTAssertEqual(player.rate ?? 0, 0)
    }

    func testPauseDuringSeekWins() throws {
        files.append(try loadSeekableFile(autoPlay: true))
        let player = FRadioPlayer.shared

        seekAndWait(to: 2, afterCall: { player.pause() })
        XCTAssertEqual(player.playbackState, .paused, "a pause issued during the seek must hold")
        XCTAssertEqual(player.rate ?? 0, 0)
    }
}
