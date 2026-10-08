//
//  DefaultsCharacterisationTests.swift
//  FRadioPlayerTests
//
//  Pins the 0.4.0 behaviour that the 0.5.0 host seams must leave intact
//  for consumers that keep the defaults: the built-in 2/4/8 s recovery
//  ladder (mid-playback only), stop() keeping the item for the next
//  play(), and interruptions auto-resuming. Seam rows: L54, L55, R04-R06.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class DefaultsCharacterisationTests: XCTestCase {

    private var fixture: URL!
    private var file: URL?

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
        if let file = file { try? FileManager.default.removeItem(at: file) }
        file = nil
        try await super.tearDown()
    }

    // MARK: - Recovery ladder

    func testDefaultLadderIsTwoFourEightSeconds() {
        XCTAssertEqual(FRadioPlayer.shared.stallRecovery.intervals, [2, 4, 8])
    }

    func testInitialBufferingDoesNotStartLadder() {
        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        player.radioURL = fixture
        XCTAssertEqual(player.playbackState, .playing)

        // Waiting before audio ever flowed is initial buffering
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertFalse(player.stallRecovery.isActive)
    }

    func testMidPlaybackStallStartsLadderAndPlayingCancelsIt() {
        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        player.radioURL = fixture

        player.handleTimeControlStatus(.playing)
        player.handleTimeControlStatus(.waitingToPlayAtSpecifiedRate)
        XCTAssertTrue(player.stallRecovery.isActive, "0.4.0 starts the ladder on a mid-playback stall")

        player.handleTimeControlStatus(.playing)
        XCTAssertFalse(player.stallRecovery.isActive, "each playing transition cancels the ladder")
    }

    // MARK: - stop() keeps the item

    func testStopDuringLoadKeepsItemAndPlayReattachesIt() throws {
        let player = FRadioPlayer.shared
        player.isAutoPlay = true
        player.radioURL = fixture
        let item = try XCTUnwrap(player.playerItem)

        player.stop()   // duration unknown yet: the live-stream branch
        XCTAssertIdentical(player.playerItem, item, "stop() keeps the item")
        XCTAssertNil(player.attachedItem, "the live branch detaches it from AVPlayer")

        player.play()
        XCTAssertIdentical(player.attachedItem, item, "play() reattaches the same item")
        XCTAssertEqual(player.playbackState, .playing)
    }

    func testStopOnFileKeepsItemAttached() throws {
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared
        let item = try XCTUnwrap(player.playerItem)

        player.stop()   // duration known: the file branch seeks to zero
        XCTAssertIdentical(player.playerItem, item)
        XCTAssertIdentical(player.attachedItem, item)

        player.play()
        XCTAssertIdentical(player.attachedItem, item)
    }

    // MARK: - Interruptions

    func testInterruptionEndAutoResumesByDefault() throws {
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared
        player.interruptionBegan()
        XCTAssertEqual(player.playbackState, .paused)
        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .playing, "0.4.0 resumes by itself")
    }
}
