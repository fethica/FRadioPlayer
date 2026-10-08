//
//  ItemConfiguratorTests.swift
//  FRadioPlayerTests
//
//  `playerItemConfigurator` lets the host touch every new item before it is
//  attached (an audio mix for the loudness tap, AU-018), and
//  `itemGeneration` proves when an item is fresh.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class ItemConfiguratorTests: XCTestCase {

    private var fixture: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        FRadioPlayer.shared.radioURL = nil
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.playerItemConfigurator = nil
        player.radioURL = nil
        player.isAutoPlay = true
        try await super.tearDown()
    }

    func testDefaultConfiguratorIsNil() {
        XCTAssertNil(FRadioPlayer.shared.playerItemConfigurator)
    }

    func testConfiguratorRunsOncePerItemBeforeAttach() throws {
        let player = FRadioPlayer.shared
        var configured: [AVPlayerItem] = []
        var attachedDuringCall = false
        var onMain = true
        player.playerItemConfigurator = { item in
            configured.append(item)
            onMain = onMain && Thread.isMainThread
            attachedDuringCall = attachedDuringCall || player.attachedItem === item || player.playerItem === item
        }

        player.radioURL = fixture
        XCTAssertEqual(configured.count, 1)
        XCTAssertIdentical(configured.first, player.playerItem, "the configured item is the one in use")
        XCTAssertIdentical(player.attachedItem, configured.first, "and the one attached to AVPlayer")
        XCTAssertFalse(attachedDuringCall, "the configurator runs before the item is attached")
        XCTAssertTrue(onMain)

        // Reattaching the kept item is not a new item
        player.stop()
        player.play()
        XCTAssertEqual(configured.count, 1)

        player.radioURL = fixture
        XCTAssertEqual(configured.count, 2)
        XCTAssertFalse(configured[0] === configured[1])
    }

    func testConfiguratorCanInstallAudioMix() throws {
        let player = FRadioPlayer.shared
        player.playerItemConfigurator = { item in
            item.audioMix = AVMutableAudioMix()
        }
        player.radioURL = fixture
        XCTAssertNotNil(try XCTUnwrap(player.playerItem).audioMix)
    }

    func testItemGenerationIncrementsPerNewItem() {
        let player = FRadioPlayer.shared
        let start = player.itemGeneration

        player.radioURL = fixture
        XCTAssertEqual(player.itemGeneration, start + 1)

        player.stop()
        player.play()
        XCTAssertEqual(player.itemGeneration, start + 1, "stop() + play() reuses the item")

        player.radioURL = fixture
        XCTAssertEqual(player.itemGeneration, start + 2)

        player.radioURL = nil
        XCTAssertEqual(player.itemGeneration, start + 2, "clearing the URL creates no item")
    }

    func testPlayAfterErrorRebuildIsANewGeneration() {
        let player = FRadioPlayer.shared
        player.radioURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).wav")
        XCTAssertTrue(waitUntil { player.state == .error })
        let failed = player.itemGeneration

        var configured = 0
        player.playerItemConfigurator = { _ in configured += 1 }
        player.play()
        XCTAssertEqual(player.itemGeneration, failed + 1)
        XCTAssertEqual(configured, 1)
    }
}
