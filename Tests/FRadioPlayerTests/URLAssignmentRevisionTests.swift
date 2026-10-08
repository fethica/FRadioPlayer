//
//  URLAssignmentRevisionTests.swift
//  FRadioPlayerTests
//
//  A radioURL assignment reports exactly one itemDidChange while it is the
//  latest assignment. An assignment superseded from inside the item
//  configurator (to nil, or to a URL whose own creation was then stopped)
//  reports nothing, and a nested same-URL rebuild does not swallow the
//  assignment's own report (re-review finding R02).
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class URLAssignmentRevisionTests: XCTestCase {

    private final class ItemRecorder: FRadioPlayerObserver {
        var items: [URL?] = []
        func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
            items.append(url)
        }
    }

    private var fixture: URL!
    private var other: URL!
    private var recorder: ItemRecorder!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        )
        other = try TestAudio.silentWAV(seconds: 1)
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        recorder = ItemRecorder()
        FRadioPlayer.shared.addObserver(recorder)
    }

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.removeObserver(recorder)
        player.playerItemConfigurator = nil
        player.radioURL = nil
        try? FileManager.default.removeItem(at: other)
        try await super.tearDown()
    }

    func testNilAssignmentInConfiguratorSupersedesTheOuterReport() throws {
        let player = FRadioPlayer.shared
        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            if calls == 1 { player.radioURL = nil }
        }

        player.radioURL = fixture

        XCTAssertNil(player.radioURL)
        XCTAssertNil(player.playerItem)
        XCTAssertEqual(player.state, .urlNotSet)
        XCTAssertEqual(recorder.items, [nil], "the latest report matches the nil URL")
    }

    func testAbortedReplacementInConfiguratorSupersedesTheOuterReport() throws {
        let player = FRadioPlayer.shared
        let other = self.other!
        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            if calls == 1 { player.radioURL = other }   // creating fixture
            if calls == 2 { player.stop() }             // creating other
        }

        player.radioURL = fixture

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(player.radioURL, other)
        XCTAssertNil(player.playerItem, "the replacement was stopped before it attached")
        XCTAssertEqual(player.playbackState, .stopped)
        XCTAssertEqual(recorder.items, [other], "the superseded assignment reports nothing after it")
    }

    func testSameURLRebuildInConfiguratorKeepsOneReport() throws {
        let player = FRadioPlayer.shared
        var calls = 0
        player.playerItemConfigurator = { _ in
            calls += 1
            if calls == 1 {
                player.stop(discardingItem: true)
                player.play()
            }
        }
        let generation = player.itemGeneration

        player.radioURL = fixture

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(player.itemGeneration, generation + 2, "the outer item and the nested fresh one")
        let item = try XCTUnwrap(player.playerItem)
        XCTAssertIdentical(player.attachedItem, item)
        XCTAssertEqual(player.playbackState, .playing)
        XCTAssertEqual(recorder.items, [fixture], "the assignment stayed current: exactly one report")
    }

    /// 0.4.0 behaviour kept with no configurator: a URL change from the
    /// `.loading` callback of a plain URL change is overwritten by the outer
    /// item, which then reports too (the outer item is the one attached).
    func testLegacyURLChangeFromLoadingStillReportsTheAttachedItem() throws {
        final class SwitchOnLoading: FRadioPlayerObserver {
            var target: URL?
            func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
                guard state == .loading, let target = target else { return }
                self.target = nil
                player.radioURL = target
            }
        }
        let player = FRadioPlayer.shared
        let switcher = SwitchOnLoading()
        switcher.target = other
        player.addObserver(switcher)
        defer { player.removeObserver(switcher) }

        player.radioURL = fixture

        XCTAssertEqual(recorder.items, [other, fixture])
        XCTAssertEqual((player.playerItem?.asset as? AVURLAsset)?.url, fixture)
    }
}
