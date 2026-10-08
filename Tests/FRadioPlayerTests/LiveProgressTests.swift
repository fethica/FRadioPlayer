//
//  LiveProgressTests.swift
//  FRadioPlayerTests
//
//  A live stream's duration starts indefinite and can stay that way, so
//  no duration change is ever observed. Progress for host watchdogs must
//  still tick (review finding S26-02), and the legacy time callbacks must
//  stay as quiet as in 0.4.0.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class LiveProgressTests: XCTestCase {

    private final class Recorder: FRadioPlayerObserver {
        var progress: [TimeInterval] = []
        var playTimes: [TimeInterval] = []
        var durations: [TimeInterval] = []
        var offMain = 0

        func radioPlayer(_ player: FRadioPlayer, didObserveProgress time: TimeInterval) {
            if !Thread.isMainThread { offMain += 1 }
            progress.append(time)
        }
        func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval) {
            playTimes.append(currentTime)
        }
        func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval) {
            durations.append(duration)
        }
    }

    private var stream: LoopbackLiveStream!
    private var recorder: Recorder!

    override func setUp() async throws {
        try await super.setUp()
        FRadioPlayer.shared.radioURL = nil
        stream = try LoopbackLiveStream()
        recorder = Recorder()
        FRadioPlayer.shared.addObserver(recorder)
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.removeObserver(recorder)
        player.radioURL = nil
        player.isAutoPlay = true
        stream.stop()
        try await super.tearDown()
    }

    private func startLive() throws -> FRadioPlayer {
        XCTAssertTrue(waitUntil(timeout: 5) { self.stream.url != nil }, "loopback listener ready")
        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        player.radioURL = try XCTUnwrap(stream.url)
        return player
    }

    /// Ticks that show time actually advanced on the periodic observer
    private func progressAdvanced() -> Bool {
        guard let first = recorder.progress.first, let last = recorder.progress.last else { return false }
        return recorder.progress.count >= 2 && last - first >= 0.9
    }

    /// The progress observer must not wait for a duration notification
    func testProgressObserverIsInstalledWhenTheItemIsAttached() throws {
        let player = try startLive()
        XCTAssertNotNil(player.playerItem)
        XCTAssertNotNil(player.liveProgressObserver, "installed at attachment, before any item KVO is delivered")
    }

    /// AVFoundation happens to post a duration KVO (indefinite) for this
    /// stream, but nothing guarantees it. Unregister the player's duration
    /// observation on the item so no duration notification can arrive,
    /// then require real ticks.
    func testLiveStreamTicksWhenNoDurationNotificationArrives() throws {
        let player = try startLive()
        let item = try XCTUnwrap(player.playerItem)
        let keyPath = #keyPath(AVPlayerItem.duration)
        item.removeObserver(player, forKeyPath: keyPath, context: FRadioPlayer.itemKVOContext)
        // Re-register before teardown replaces the item and removes it
        defer { item.addObserver(player, forKeyPath: keyPath, options: [.old, .new], context: FRadioPlayer.itemKVOContext) }

        XCTAssertTrue(waitUntil(timeout: 10) { self.progressAdvanced() }, "ticks: \(recorder.progress), state: \(player.state)")
        XCTAssertTrue(CMTIME_IS_INDEFINITE(item.duration), "the stream stayed live: \(item.duration)")
        XCTAssertEqual(recorder.offMain, 0)
        XCTAssertEqual(recorder.playTimes, [])
    }

    func testIndefiniteLiveStreamTicksWithoutADurationChange() throws {
        let player = try startLive()
        XCTAssertTrue(waitUntil(timeout: 10) { self.progressAdvanced() }, "ticks: \(recorder.progress), state: \(player.state)")

        let item = try XCTUnwrap(player.playerItem)
        XCTAssertTrue(CMTIME_IS_INDEFINITE(item.duration), "the stream stayed live: \(item.duration)")
        XCTAssertEqual(recorder.offMain, 0)

        // Legacy callbacks stay as 0.4.0 left them for a live stream
        XCTAssertEqual(recorder.playTimes, [], "playTimeDidChange is not called for live streams")
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertEqual(recorder.durations, [])
    }

    func testDiscardingStopEndsLiveTicksAndPlayResumesThem() throws {
        let player = try startLive()
        XCTAssertTrue(waitUntil(timeout: 10) { self.progressAdvanced() }, "ticks: \(recorder.progress)")

        player.stop(discardingItem: true)
        recorder.progress.removeAll()
        settle(for: 1.2)
        XCTAssertEqual(recorder.progress, [], "no ticks without an item")

        player.play()
        XCTAssertTrue(waitUntil(timeout: 10) { self.progressAdvanced() }, "the fresh item ticks: \(recorder.progress)")
    }
}
