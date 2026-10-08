//
//  InterruptionResumeSeamTests.swift
//  FRadioPlayerTests
//
//  `resumesAfterInterruption = false` hands the resume decision to the
//  host's single playback authority (AU-009 prerequisite). The library
//  still tracks whether a resume is warranted and reports it.
//

import XCTest
#if os(iOS)
import AVFoundation
#endif
@testable import FRadioPlayer

@MainActor
final class InterruptionResumeSeamTests: XCTestCase {

    private final class Recorder: FRadioPlayerObserver {
        var ended: [Bool] = []
        var playbackAtCallback: [FRadioPlayer.PlaybackState] = []
        func radioPlayer(_ player: FRadioPlayer, interruptionEnded shouldResume: Bool) {
            ended.append(shouldResume)
            playbackAtCallback.append(player.playbackState)
        }
    }

    private var file: URL?
    private var recorder: Recorder!

    override func setUp() async throws {
        try await super.setUp()
        recorder = Recorder()
        FRadioPlayer.shared.addObserver(recorder)
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.removeObserver(recorder)
        player.resumesAfterInterruption = true
        player.radioURL = nil
        player.isAutoPlay = true
        if let file = file { try? FileManager.default.removeItem(at: file) }
        file = nil
        try await super.tearDown()
    }

    private func startPlaying() throws -> FRadioPlayer {
        file = try loadSeekableFile(autoPlay: true)
        XCTAssertEqual(FRadioPlayer.shared.playbackState, .playing)
        return FRadioPlayer.shared
    }

    func testDefaultResumesAndReports() throws {
        let player = try startPlaying()
        XCTAssertTrue(player.resumesAfterInterruption)
        player.interruptionBegan()
        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertEqual(recorder.ended, [true])
        XCTAssertEqual(recorder.playbackAtCallback, [.playing], "reported after the library resumed")
    }

    func testHostDecidesWhenAutoResumeIsOff() throws {
        let player = try startPlaying()
        player.resumesAfterInterruption = false
        player.interruptionBegan()
        XCTAssertEqual(player.playbackState, .paused)

        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .paused, "the library must not call play()")
        XCTAssertEqual(recorder.ended, [true], "the host is told a resume is warranted")

        player.play()   // the host's decision
        XCTAssertEqual(player.playbackState, .playing)
    }

    func testSystemSaysNoResume() throws {
        let player = try startPlaying()
        player.resumesAfterInterruption = false
        player.interruptionBegan()
        player.interruptionEnded(shouldResume: false)
        XCTAssertEqual(player.playbackState, .paused)
        XCTAssertEqual(recorder.ended, [false])
    }

    func testUserPauseDuringInterruptionReportsNoResume() throws {
        let player = try startPlaying()
        player.resumesAfterInterruption = false
        player.interruptionBegan()
        player.pause()
        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .paused)
        XCTAssertEqual(recorder.ended, [false], "a user pause during the interruption holds")
    }

    func testPausedBeforeInterruptionReportsNoResume() throws {
        let player = try startPlaying()
        player.pause()
        player.interruptionBegan()
        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .paused)
        XCTAssertEqual(recorder.ended, [false])
    }

    #if os(iOS)
    func testNotificationPathRespectsAutoResumeOff() throws {
        let player = try startPlaying()
        player.resumesAfterInterruption = false

        func post(_ type: AVAudioSession.InterruptionType, _ options: AVAudioSession.InterruptionOptions? = nil) {
            var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
            if let options = options { userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue }
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: userInfo)
        }

        post(.began)
        XCTAssertTrue(waitUntil { player.playbackState == .paused })
        post(.ended, .shouldResume)
        XCTAssertTrue(waitUntil { self.recorder.ended == [true] })
        settle(for: 0.2)
        XCTAssertEqual(player.playbackState, .paused)
    }
    #endif
}
