//
//  HostManagedRecoveryTests.swift
//  FRadioPlayerTests
//
//  RecoveryPolicy and the watchdog observations. Under `.hostManaged` the
//  library never schedules a reload: stall signals are reported and the
//  host owns the ladder (AU-009..AU-014 prerequisite, ledger L54/R04).
//  Under `.automatic` the 0.4.0 ladder runs as before and the same
//  signals are reported on top.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class HostManagedRecoveryTests: XCTestCase {

    private final class Recorder: FRadioPlayerObserver {
        var stalls: [FRadioPlayer.StallReason] = []
        var buffering: [Bool] = []
        var progress: [TimeInterval] = []
        var offMain = 0

        func radioPlayerDidDetectStall(_ player: FRadioPlayer, reason: FRadioPlayer.StallReason) {
            if !Thread.isMainThread { offMain += 1 }
            stalls.append(reason)
        }
        func radioPlayer(_ player: FRadioPlayer, bufferingDidChange isBuffering: Bool) {
            if !Thread.isMainThread { offMain += 1 }
            buffering.append(isBuffering)
        }
        func radioPlayer(_ player: FRadioPlayer, didObserveProgress time: TimeInterval) {
            if !Thread.isMainThread { offMain += 1 }
            progress.append(time)
        }
    }

    private var fixture: URL!
    private var file: URL?
    private var recorder: Recorder!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        FRadioPlayer.shared.radioURL = nil
        recorder = Recorder()
        FRadioPlayer.shared.addObserver(recorder)
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.removeObserver(recorder)
        player.radioURL = nil
        player.isAutoPlay = true
        player.recoveryPolicy = .automatic
        player.connectivityDidChange(isConnected: true)
        if let file = file { try? FileManager.default.removeItem(at: file) }
        file = nil
        try await super.tearDown()
    }

    private func startFixture(policy: FRadioPlayer.RecoveryPolicy) -> FRadioPlayer {
        let player = FRadioPlayer.shared
        player.recoveryPolicy = policy
        player.isAutoPlay = true
        player.radioURL = fixture
        XCTAssertEqual(player.playbackState, .playing)
        return player
    }

    // MARK: - Policy

    func testDefaultPolicyIsAutomatic() {
        XCTAssertEqual(FRadioPlayer.shared.recoveryPolicy, .automatic)
    }

    func testHostManagedMidPlaybackStallSchedulesNothing() {
        let player = startFixture(policy: .hostManaged)
        player.handleTimeControlStatus(.playing)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertFalse(player.stallRecovery.isActive, "host-managed must never schedule a reload")
        XCTAssertEqual(player.state, .loading, "the loading vocabulary still tracks the stall")
        XCTAssertEqual(recorder.buffering, [true])
    }

    func testHostManagedBufferEmptyIsReportedNotRecovered() throws {
        let player = startFixture(policy: .hostManaged)
        let item = try XCTUnwrap(player.playerItem)
        player.handleTimeControlStatus(.playing)

        player.bufferEmptyDidChange(item, isEmpty: true)
        XCTAssertEqual(recorder.stalls, [.bufferEmpty])
        XCTAssertFalse(player.stallRecovery.isActive)
        XCTAssertEqual(recorder.buffering, [true])
    }

    func testHostManagedReconnectIsReported() {
        let player = startFixture(policy: .hostManaged)
        player.connectivityDidChange(isConnected: false)
        player.connectivityDidChange(isConnected: true)
        XCTAssertEqual(recorder.stalls, [.networkReconnected])
        XCTAssertFalse(player.stallRecovery.isActive)
    }

    func testPlaybackStalledNotificationIsReported() throws {
        let player = startFixture(policy: .hostManaged)
        let item = try XCTUnwrap(player.playerItem)
        NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: item)
        XCTAssertTrue(waitUntil(timeout: 2) { self.recorder.stalls == [.playbackStalledNotification] })
        XCTAssertFalse(player.stallRecovery.isActive)
        XCTAssertEqual(recorder.offMain, 0)
    }

    func testStalledNotificationFromBackgroundThreadHops() throws {
        let player = startFixture(policy: .hostManaged)
        let item = try XCTUnwrap(player.playerItem)
        DispatchQueue.global().async {
            NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: item)
        }
        XCTAssertTrue(waitUntil(timeout: 2) { self.recorder.stalls == [.playbackStalledNotification] })
        XCTAssertEqual(recorder.offMain, 0)
    }

    func testStallsAreNotReportedWithoutPlaybackIntent() throws {
        let player = startFixture(policy: .hostManaged)
        let item = try XCTUnwrap(player.playerItem)
        player.pause()
        player.bufferEmptyDidChange(item, isEmpty: true)
        player.connectivityDidChange(isConnected: false)
        player.connectivityDidChange(isConnected: true)
        XCTAssertEqual(recorder.stalls, [])
    }

    func testSwitchingToHostManagedCancelsActiveLadder() {
        let player = startFixture(policy: .automatic)
        player.handleTimeControlStatus(.playing)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertTrue(player.stallRecovery.isActive)

        player.recoveryPolicy = .hostManaged
        XCTAssertFalse(player.stallRecovery.isActive, "the host takes over: no library reload may remain scheduled")
    }

    func testAutomaticKeepsLadderAndAlsoReports() throws {
        let player = startFixture(policy: .automatic)
        let item = try XCTUnwrap(player.playerItem)
        player.handleTimeControlStatus(.playing)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertTrue(player.stallRecovery.isActive, "automatic is exactly the 0.4.0 ladder")

        player.bufferEmptyDidChange(item, isEmpty: true)
        XCTAssertEqual(recorder.stalls, [.bufferEmpty])
    }

    // MARK: - Buffering

    func testBufferingTransitionsAreDedupedAndEndOnPlayingPauseStop() {
        let player = startFixture(policy: .hostManaged)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        player.handleTimeControlStatus(.playing)
        player.handleTimeControlStatus(.playing)
        XCTAssertEqual(recorder.buffering, [true, false])

        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        player.pause()
        XCTAssertEqual(recorder.buffering, [true, false, true, false])

        player.play()
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        player.stop()
        XCTAssertEqual(recorder.buffering, [true, false, true, false, true, false])
        XCTAssertEqual(recorder.offMain, 0)
    }

    // MARK: - Progress

    /// Ticks that prove time moved on the periodic observer, not only the
    /// immediate callbacks AVPlayer makes when the observer is added
    private func progressAdvanced() -> Bool {
        guard let first = recorder.progress.first, let last = recorder.progress.last else { return false }
        return recorder.progress.count >= 2 && last - first >= 0.4
    }

    func testProgressTicksArriveOnMainActorForFiles() throws {
        file = try loadSeekableFile(autoPlay: true)
        XCTAssertTrue(waitUntil(timeout: 5) { self.progressAdvanced() }, "ticks: \(recorder.progress)")
        XCTAssertEqual(recorder.offMain, 0)
    }

    func testProgressTicksArriveForLiveStreams() throws {
        // A live stream reports an indefinite duration; the file time
        // observer is removed, and progress must keep ticking for watchdogs
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared
        player.durationDidChange(.indefinite)
        XCTAssertEqual(player.duration, 0)
        XCTAssertNotNil(player.liveProgressObserver, "live streams get a progress-only observer")
        recorder.progress.removeAll()

        XCTAssertTrue(waitUntil(timeout: 5) { self.progressAdvanced() }, "ticks: \(recorder.progress)")
        XCTAssertEqual(recorder.offMain, 0)

        player.radioURL = nil
        XCTAssertNil(player.liveProgressObserver, "a URL change removes it")
    }
}
