//
//  ConnectivitySnapshotTests.swift
//  FRadioPlayerTests
//
//  NWPathMonitor delivers the current path right after it starts. That
//  first satisfied snapshot is not a lost-then-restored connection and must
//  not be reported as `.networkReconnected` (review finding S26-04). A
//  satisfied path after a known unsatisfied one is a restoration, cold
//  start or not.
//

import XCTest
@testable import FRadioPlayer

@MainActor
final class ConnectivitySnapshotTests: XCTestCase {

    private final class Recorder: FRadioPlayerObserver {
        var stalls: [FRadioPlayer.StallReason] = []
        func radioPlayerDidDetectStall(_ player: FRadioPlayer, reason: FRadioPlayer.StallReason) {
            stalls.append(reason)
        }
    }

    private var fixture: URL!
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
        player.recoveryPolicy = .automatic
        player.connectivityDidChange(isConnected: true)
        try await super.tearDown()
    }

    /// Playback intent before the monitor's first snapshot, as when a host
    /// starts playing right after first touching `shared`
    private func coldStartPlaying(policy: FRadioPlayer.RecoveryPolicy) -> FRadioPlayer {
        let player = FRadioPlayer.shared
        player.connectivity = FRadioPlayer.Connectivity()
        player.recoveryPolicy = policy
        player.isAutoPlay = true
        player.radioURL = fixture
        XCTAssertEqual(player.playbackState, .playing)
        return player
    }

    func testFirstSatisfiedSnapshotIsNotAReconnect() {
        let player = coldStartPlaying(policy: .hostManaged)
        player.connectivityDidChange(isConnected: true)
        XCTAssertEqual(recorder.stalls, [], "the initial snapshot only seeds connectivity")
        XCTAssertTrue(player.connectivity.isConnected)

        // A real loss and return afterwards is reported
        player.connectivityDidChange(isConnected: false)
        player.connectivityDidChange(isConnected: true)
        XCTAssertEqual(recorder.stalls, [.networkReconnected])
    }

    func testSatisfiedAfterAnUnsatisfiedFirstSnapshotIsAReconnect() {
        let player = coldStartPlaying(policy: .hostManaged)
        player.connectivityDidChange(isConnected: false)
        XCTAssertEqual(recorder.stalls, [])
        player.connectivityDidChange(isConnected: true)
        XCTAssertEqual(recorder.stalls, [.networkReconnected], "started offline, then came back")
    }

    func testAutomaticColdStartNeitherReportsNorStartsTheLadder() {
        let player = coldStartPlaying(policy: .automatic)
        player.handleTimeControlStatus(.playing)
        player.connectivityDidChange(isConnected: true)
        XCTAssertEqual(recorder.stalls, [])
        XCTAssertFalse(player.stallRecovery.isActive)
    }
}
