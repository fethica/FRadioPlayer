//
//  AudioSessionConfigurationTests.swift
//  FRadioPlayerTests
//
//  `configuresAudioSession` gates the category the player applies when
//  `shared` is first created. The singleton is created once per process,
//  so the gate is tested directly rather than through a second init.
//

import XCTest
#if !os(macOS)
import AVFoundation
#endif
@testable import FRadioPlayer

@MainActor
final class AudioSessionConfigurationTests: XCTestCase {

    private var original = true

    override func setUp() async throws {
        try await super.setUp()
        original = FRadioPlayer.configuresAudioSession
    }

    override func tearDown() async throws {
        FRadioPlayer.configuresAudioSession = original
        try await super.tearDown()
    }

    func testConfiguresAudioSessionByDefault() {
        XCTAssertTrue(original, "0.3.0 behaviour: the player configures the session unless told otherwise")
    }

    #if !os(macOS)
    func testPlaybackCategoryAppliesToRealAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        let previous = (session.category, session.mode, session.categoryOptions)
        defer { try? session.setCategory(previous.0, mode: previous.1, options: previous.2) }
        try session.setCategory(.soloAmbient, mode: .default, options: [])

        try FRadioPlayer.applyPlaybackCategory()

        XCTAssertEqual(session.category, .playback)
        XCTAssertFalse(session.categoryOptions.contains(.mixWithOthers))
        XCTAssertFalse(session.categoryOptions.contains(.allowAirPlay),
                       "AirPlay is implicit for playback; its explicit option is only valid for playAndRecord")
    }
    #endif

    func testGateAppliesCategoryWhenEnabled() {
        FRadioPlayer.configuresAudioSession = true
        var applied = 0
        FRadioPlayer.configureAudioSessionIfNeeded { applied += 1 }
        XCTAssertEqual(applied, 1)
    }

    func testGateSkipsCategoryWhenDisabled() {
        FRadioPlayer.configuresAudioSession = false
        var applied = 0
        FRadioPlayer.configureAudioSessionIfNeeded { applied += 1 }
        XCTAssertEqual(applied, 0, "an app that owns its audio session must not have its category overwritten")
    }
}
