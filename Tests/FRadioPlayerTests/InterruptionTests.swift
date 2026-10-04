//
//  InterruptionTests.swift
//  FRadioPlayerTests
//
//  An interruption that ends with shouldResume resumes only what was
//  playing when it began: a user pause, before or during the
//  interruption, holds. The seam tests run on every platform; the
//  notification tests drive the real AVAudioSession entry points on iOS.
//

import XCTest
#if os(iOS)
import AVFoundation
#endif
@testable import FRadioPlayer

@MainActor
final class InterruptionTests: XCTestCase {

    private var file: URL?

    override func tearDown() async throws {
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        if let file = file { try? FileManager.default.removeItem(at: file) }
        try await super.tearDown()
    }

    /// Starts playback of a generated file. Called from each synchronous
    /// test: the run loop that delivers item KVO does not spin inside an
    /// async setUp.
    private func startPlaying() throws {
        file = try loadSeekableFile(autoPlay: true)
        XCTAssertEqual(FRadioPlayer.shared.playbackState, .playing)
    }

    func testResumesWhenPlayingAtInterruption() throws {
        try startPlaying()
        let player = FRadioPlayer.shared
        player.interruptionBegan()
        XCTAssertEqual(player.playbackState, .paused)

        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .playing)
    }

    func testUserPauseBeforeInterruptionHolds() throws {
        try startPlaying()
        let player = FRadioPlayer.shared
        player.pause()

        player.interruptionBegan()
        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .paused, "shouldResume must not override a user pause")
    }

    func testUserPauseDuringInterruptionHolds() throws {
        try startPlaying()
        let player = FRadioPlayer.shared
        player.interruptionBegan()
        player.pause()

        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .paused, "a pause issued during the interruption must hold")
    }

    func testRepeatedBeganKeepsResumeIntent() throws {
        try startPlaying()
        let player = FRadioPlayer.shared
        player.interruptionBegan()
        player.interruptionBegan()

        player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(player.playbackState, .playing)
    }

    func testEndedWithoutShouldResumeStaysPaused() throws {
        try startPlaying()
        let player = FRadioPlayer.shared
        player.interruptionBegan()
        player.interruptionEnded(shouldResume: false)
        XCTAssertEqual(player.playbackState, .paused)
    }

    #if os(iOS)
    // MARK: - Real notification entry points

    private func postInterruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions? = nil) {
        var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let options = options {
            userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: userInfo)
    }

    func testInterruptionNotificationsRespectUserPause() throws {
        try startPlaying()
        let player = FRadioPlayer.shared
        player.pause()

        postInterruption(.began)
        postInterruption(.ended, options: .shouldResume)
        settle(for: 0.3)
        XCTAssertEqual(player.playbackState, .paused)
    }

    func testInterruptionNotificationsResumePlayback() throws {
        try startPlaying()
        let player = FRadioPlayer.shared

        postInterruption(.began)
        XCTAssertTrue(waitUntil { player.playbackState == .paused })
        postInterruption(.ended, options: .shouldResume)
        XCTAssertTrue(waitUntil { player.playbackState == .playing })
    }

    func testRouteChangeFromBackgroundThreadPauses() throws {
        try startPlaying()
        // AVAudioSession posts route changes on a secondary thread
        let player = FRadioPlayer.shared
        DispatchQueue.global().async {
            NotificationCenter.default.post(
                name: AVAudioSession.routeChangeNotification,
                object: nil,
                userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
            )
        }
        XCTAssertTrue(waitUntil { player.playbackState == .paused })
    }
    #endif
}
