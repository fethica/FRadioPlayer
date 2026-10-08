//
//  FailureClassificationTests.swift
//  FRadioPlayerTests
//
//  `.error` now carries a classification: the host's ladder retries
//  network/timeout failures and stops on not-found and decode ones
//  (AU-005, AU-010..AU-012 prerequisite; ledger L55/R05). The classifier
//  is pure; the player feeds it the item's error and last error-log event.
//

import XCTest
import AVFoundation
@testable import FRadioPlayer

@MainActor
final class FailureClassificationTests: XCTestCase {

    private typealias Failure = FRadioPlayer.Failure

    override func tearDown() async throws {
        FRadioPlayer.shared.radioURL = nil
        FRadioPlayer.shared.isAutoPlay = true
        try await super.tearDown()
    }

    /// AVFoundation's usual wrapping: a generic AV error over the cause
    private func avWrapping(_ underlying: NSError, code: Int = AVError.unknown.rawValue) -> NSError {
        NSError(domain: AVFoundationErrorDomain, code: code, userInfo: [
            NSUnderlyingErrorKey: underlying,
            NSLocalizedDescriptionKey: "The operation could not be completed",
        ])
    }

    // MARK: - Network family

    func testNotConnectedIsNetwork() {
        let cause = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let failure = Failure.classify(error: avWrapping(cause), errorLog: nil)
        XCTAssertEqual(failure.kind, .network)
        XCTAssertEqual(failure.domain, AVFoundationErrorDomain, "domain and code describe the reported error")
        XCTAssertEqual(failure.code, AVError.unknown.rawValue)
        XCTAssertNil(failure.httpStatus)
        XCTAssertEqual(failure.message, "The operation could not be completed")
    }

    func testConnectionLostIsNetwork() {
        let cause = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        XCTAssertEqual(Failure.classify(error: cause, errorLog: nil).kind, .network)
    }

    func testTimedOutIsTimeout() {
        let cause = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(Failure.classify(error: avWrapping(cause), errorLog: nil).kind, .timeout)
    }

    // MARK: - HTTP status from the error log

    func testErrorLog404IsNotFound() {
        let log = FRadioPlayer.ErrorLogEntry(statusCode: 404, domain: "CoreMediaErrorDomain", comment: nil)
        let failure = Failure.classify(error: avWrapping(NSError(domain: "CoreMediaErrorDomain", code: -12938)), errorLog: log)
        XCTAssertEqual(failure.kind, .notFound)
        XCTAssertEqual(failure.httpStatus, 404)
    }

    func testErrorLog403IsForbidden() {
        let log = FRadioPlayer.ErrorLogEntry(statusCode: 403, domain: "CoreMediaErrorDomain", comment: nil)
        let failure = Failure.classify(error: nil, errorLog: log)
        XCTAssertEqual(failure.kind, .forbidden)
        XCTAssertEqual(failure.httpStatus, 403)
        XCTAssertEqual(failure.domain, "CoreMediaErrorDomain", "without an error the log event describes it")
        XCTAssertEqual(failure.code, 403)
    }

    func testErrorLogCommentCarriesStatus() {
        // CoreMedia reports its own negative code and the status in the comment
        let log = FRadioPlayer.ErrorLogEntry(statusCode: -12938, domain: "CoreMediaErrorDomain", comment: "HTTP 404: File Not Found")
        let failure = Failure.classify(error: nil, errorLog: log)
        XCTAssertEqual(failure.kind, .notFound)
        XCTAssertEqual(failure.httpStatus, 404)
        XCTAssertEqual(failure.message, "HTTP 404: File Not Found")
    }

    func testErrorLog401IsUnauthorized() {
        let log = FRadioPlayer.ErrorLogEntry(statusCode: -12937, domain: "CoreMediaErrorDomain", comment: "HTTP 401: Unauthorized")
        XCTAssertEqual(Failure.classify(error: nil, errorLog: log).kind, .unauthorized)
    }

    func testServerErrorIsNetwork() {
        let log = FRadioPlayer.ErrorLogEntry(statusCode: 503, domain: "CoreMediaErrorDomain", comment: nil)
        XCTAssertEqual(Failure.classify(error: nil, errorLog: log).kind, .network)
    }

    func testHTTPStatusWinsOverTransportError() {
        let log = FRadioPlayer.ErrorLogEntry(statusCode: 404, domain: "CoreMediaErrorDomain", comment: nil)
        let cause = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        XCTAssertEqual(Failure.classify(error: avWrapping(cause), errorLog: log).kind, .notFound)
    }

    // MARK: - Decode and others

    func testDecodeFailures() {
        for code in [AVError.decodeFailed, .fileFormatNotRecognized, .failedToParse, .undecodableMediaData, .decoderNotFound] {
            let error = NSError(domain: AVFoundationErrorDomain, code: code.rawValue)
            XCTAssertEqual(Failure.classify(error: error, errorLog: nil).kind, .decode, "\(code)")
        }
        let cannotDecode = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeContentData)
        XCTAssertEqual(Failure.classify(error: avWrapping(cannotDecode), errorLog: nil).kind, .decode)
    }

    func testMissingFileIsNotFound() {
        let cause = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)
        XCTAssertEqual(Failure.classify(error: avWrapping(cause), errorLog: nil).kind, .notFound)
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertEqual(Failure.classify(error: avWrapping(cocoa), errorLog: nil).kind, .notFound)
    }

    func testUnclassifiedIsUnknown() {
        let failure = Failure.classify(error: NSError(domain: "Elsewhere", code: 7), errorLog: nil)
        XCTAssertEqual(failure.kind, .unknown)
        XCTAssertEqual(failure.domain, "Elsewhere")
        XCTAssertEqual(failure.code, 7)
        XCTAssertEqual(Failure.classify(error: nil, errorLog: nil).kind, .unknown)
    }

    // MARK: - Player wiring

    private final class Recorder: FRadioPlayerObserver {
        var events: [String] = []
        var failures: [FRadioPlayer.Failure] = []
        var lastFailureAtCallback: FRadioPlayer.Failure?
        var stateAtCallback: FRadioPlayer.State?
        func radioPlayer(_ player: FRadioPlayer, didFail failure: FRadioPlayer.Failure) {
            events.append("didFail")
            failures.append(failure)
            lastFailureAtCallback = player.lastFailure
            stateAtCallback = player.state
        }
        func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
            if state == .error { events.append("error") }
        }
    }

    func testFailedItemReportsFailureBeforeErrorState() {
        let player = FRadioPlayer.shared
        let recorder = Recorder()
        player.addObserver(recorder)
        defer { player.removeObserver(recorder) }

        player.radioURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).mp3")
        XCTAssertTrue(waitUntil { player.state == .error })

        XCTAssertEqual(recorder.events, ["didFail", "error"], "didFail precedes the .error state")
        XCTAssertNotEqual(recorder.stateAtCallback, .error)
        XCTAssertEqual(recorder.lastFailureAtCallback, recorder.failures.first, "lastFailure is set before didFail")
        // A missing local file surfaces as AVFoundation -11800 over an
        // undocumented OSStatus (-17913 on macOS 27), so it stays .unknown:
        // the classifier only maps documented codes
        XCTAssertEqual(player.lastFailure?.domain, AVFoundationErrorDomain)
        XCTAssertNotNil(player.lastFailure?.message)
    }

    func testStallExhaustionFailsWithStalledExhausted() {
        let player = FRadioPlayer.shared
        let recorder = Recorder()
        player.addObserver(recorder)
        defer { player.removeObserver(recorder) }

        let fixture = Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")!
        player.radioURL = fixture
        player.stallRecovery.onExhausted?()

        XCTAssertEqual(player.state, .error)
        XCTAssertEqual(player.lastFailure?.kind, .stalledExhausted)
        XCTAssertEqual(recorder.events, ["didFail", "error"])
    }

    func testNewURLClearsLastFailure() {
        let player = FRadioPlayer.shared
        player.radioURL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).mp3")
        XCTAssertTrue(waitUntil { player.state == .error })
        XCTAssertNotNil(player.lastFailure)

        player.radioURL = Bundle.module.url(forResource: "silence", withExtension: "wav", subdirectory: "Fixtures")
        XCTAssertNil(player.lastFailure, "a new item starts without a failure")
    }
}
