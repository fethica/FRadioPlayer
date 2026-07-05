//
//  PlaybackFixtureTests.swift
//  FRadioPlayerTests
//
//  Basic state-transition coverage using a bundled audio fixture.
//  AVPlayer plays local files, so this exercises the real loading path
//  without any network. Live-stream-specific behavior is out of scope
//  here and gets covered at a seam in a future version.
//

import XCTest
import FRadioPlayer

final class PlaybackFixtureTests: XCTestCase {

    private final class StateRecorder: FRadioPlayerObserver {
        var onState: ((FRadioPlayer.State) -> Void)?
        func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
            onState?(state)
        }
    }

    private var recorder: StateRecorder?

    override func tearDown() {
        if let recorder = recorder {
            FRadioPlayer.shared.removeObserver(recorder)
        }
        recorder = nil
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        super.tearDown()
    }

    func testLocalFileReachesReadyToPlay() throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures"),
            "bundled test fixture missing"
        )

        let player = FRadioPlayer.shared
        player.isAutoPlay = false

        let ready = expectation(description: "player reaches readyToPlay or loadingFinished")
        ready.assertForOverFulfill = false

        let recorder = StateRecorder()
        self.recorder = recorder
        recorder.onState = { state in
            if state == .readyToPlay || state == .loadingFinished {
                ready.fulfill()
            }
        }
        player.addObserver(recorder)

        player.radioURL = fixture
        XCTAssertEqual(player.state, .loading, "setting a URL must synchronously enter loading")

        wait(for: [ready], timeout: 10)
    }

    func testClearingURLResetsState() {
        let player = FRadioPlayer.shared
        player.radioURL = nil
        XCTAssertEqual(player.state, .urlNotSet)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.duration, 0)
    }
}
