//
//  CallbackDeliveryTests.swift
//  FRadioPlayerTests
//
//  AVFoundation entry points that can arrive off the main thread must hop
//  to the main actor instead of trapping or racing. Each test delivers a
//  callback from a background queue and checks the player state it drives.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class CallbackDeliveryTests: XCTestCase {

    private var file: URL?
    private var originalArtworkAPI: FRadioArtworkAPI?

    override func tearDown() async throws {
        let player = FRadioPlayer.shared
        player.radioURL = nil
        player.isAutoPlay = true
        player.enableArtwork = true
        if let api = originalArtworkAPI { player.artworkAPI = api }
        originalArtworkAPI = nil
        if let file = file { try? FileManager.default.removeItem(at: file) }
        file = nil
        try await super.tearDown()
    }

    // MARK: - Item KVO

    func testItemStatusKVOFromBackgroundQueueHops() throws {
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared
        let item = try XCTUnwrap(player.playerItem)

        // A failed status the real item never reports, so only the
        // background delivery can produce the error state. The event
        // carries Sendable values only, as observeValue produces it.
        let event = PlayerItemKVOEvent(
            keyPath: #keyPath(AVPlayerItem.status),
            itemID: ObjectIdentifier(item),
            newStatus: AVPlayerItem.Status.failed.rawValue
        )
        DispatchQueue.global().async {
            player.receiveItemKVO(event)
        }

        XCTAssertTrue(waitUntil { player.state == .error }, "off-main KVO must reach the main actor")
        XCTAssertEqual(player.playbackState, .stopped)
    }

    func testObserveValueFromBackgroundQueueDoesNotTrap() throws {
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared

        // The real override, called off the main thread with our context
        // for an item that is not the current one: it must hop, then drop
        // the event, instead of trapping on an actor assumption
        let failed = AVPlayerItem.Status.failed.rawValue
        let delivered = expectation(description: "background KVO delivered")
        let url = try XCTUnwrap(file)
        DispatchQueue.global().async {
            let detached = AVPlayerItem(url: url)
            player.observeValue(
                forKeyPath: #keyPath(AVPlayerItem.status),
                of: detached,
                change: [.newKey: NSNumber(value: failed)],
                context: FRadioPlayer.itemKVOContext
            )
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        settle(for: 0.2)
        // The real item may finish loading meanwhile; only the injected
        // failure must not land
        XCTAssertNotEqual(player.state, .error, "KVO for an item that is not current must be ignored")
        XCTAssertEqual(player.playbackState, .playing)
    }

    // MARK: - Notifications

    func testPlayedToEndFromBackgroundQueueHops() throws {
        file = try loadSeekableFile(autoPlay: true)
        let player = FRadioPlayer.shared
        XCTAssertEqual(player.playbackState, .playing)

        // AVPlayerItemDidPlayToEndTime may post on any thread
        DispatchQueue.global().async {
            player.itemDidPlayToEnd()
        }
        XCTAssertTrue(waitUntil { player.playbackState == .paused })
    }

    // MARK: - Metadata and artwork

    private func timedMetadata(_ value: String) -> [AVTimedMetadataGroup] {
        let item = AVMutableMetadataItem()
        item.value = value as NSString
        return [AVTimedMetadataGroup(items: [item], timeRange: CMTimeRange(start: .zero, duration: .zero))]
    }

    /// Resolves artwork for "slow" later than for anything else, off the main queue
    private struct DelayedArtworkAPI: FRadioArtworkAPI {
        func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping @Sendable (URL?) -> Void) {
            let raw = metadata.rawValue ?? ""
            let delay: TimeInterval = raw == "slow" ? 0.3 : 0
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                completion(URL(string: "https://artwork.test/\(raw)"))
            }
        }
    }

    /// Holds each lookup until the test releases it, then reports delivery
    private struct GatedArtworkAPI: FRadioArtworkAPI {
        let gates: [String: DispatchSemaphore]
        let delivered: [String: XCTestExpectation]

        func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping @Sendable (URL?) -> Void) {
            let raw = metadata.rawValue ?? ""
            let gate = gates[raw]
            let done = delivered[raw]
            DispatchQueue.global().async {
                gate?.wait()
                completion(URL(string: "https://artwork.test/\(raw)"))
                done?.fulfill()
            }
        }
    }

    func testArtworkForPreviousStationDoesNotLandOnNextStation() throws {
        let player = FRadioPlayer.shared
        originalArtworkAPI = player.artworkAPI
        let gateA = DispatchSemaphore(value: 0)
        let gateB = DispatchSemaphore(value: 0)
        let deliveredA = expectation(description: "A lookup delivered")
        let deliveredB = expectation(description: "B lookup delivered")
        player.artworkAPI = GatedArtworkAPI(gates: ["A": gateA, "B": gateB],
                                            delivered: ["A": deliveredA, "B": deliveredB])
        player.enableArtwork = true
        player.isAutoPlay = false

        // Station A reports a track; its artwork lookup is in flight
        let stationA = try TestAudio.silentWAV(seconds: 1)
        let stationB = try TestAudio.silentWAV(seconds: 1)
        defer {
            try? FileManager.default.removeItem(at: stationA)
            try? FileManager.default.removeItem(at: stationB)
        }
        player.radioURL = stationA
        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: timedMetadata("A"), from: nil)

        // The user switches to station B before A's lookup returns
        player.radioURL = stationB
        XCTAssertNil(player.currentArtworkURL)

        // A's response arrives late: it must not land on B
        gateA.signal()
        wait(for: [deliveredA], timeout: 5)
        settle(for: 0.2)
        XCTAssertNil(player.currentArtworkURL, "station A's artwork must not appear on station B")

        // B reports its own track, and only B's artwork is shown
        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: timedMetadata("B"), from: nil)
        gateB.signal()
        wait(for: [deliveredB], timeout: 5)
        XCTAssertTrue(waitUntil { player.currentArtworkURL != nil })
        XCTAssertEqual(player.currentArtworkURL?.lastPathComponent, "B")
    }

    func testMetadataDeliveryUpdatesCurrentMetadata() {
        let player = FRadioPlayer.shared
        player.enableArtwork = false

        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: timedMetadata("Artist - Track"), from: nil)
        XCTAssertEqual(player.currentMetadata?.artistName, "Artist")
        XCTAssertEqual(player.currentMetadata?.trackName, "Track")
    }

    func testStaleArtworkDoesNotOverwriteNewerTrack() {
        let player = FRadioPlayer.shared
        originalArtworkAPI = player.artworkAPI
        player.artworkAPI = DelayedArtworkAPI()
        player.enableArtwork = true

        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: timedMetadata("slow"), from: nil)
        player.metadataOutput(player.metadataOutput, didOutputTimedMetadataGroups: timedMetadata("fast"), from: nil)

        XCTAssertTrue(waitUntil { player.currentArtworkURL != nil })
        settle(for: 0.5)
        XCTAssertEqual(player.currentArtworkURL?.lastPathComponent, "fast",
                       "a late artwork lookup for an older track must be dropped")
    }
}
