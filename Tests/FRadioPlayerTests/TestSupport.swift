//
//  TestSupport.swift
//  FRadioPlayerTests
//
//  Shared helpers: a generated audio file long enough to seek in (the
//  bundled fixture is 0.2 seconds), and a run-loop wait for conditions
//  that settle through main-actor hops.
//

import XCTest
@testable import FRadioPlayer

enum TestAudio {

    /// Writes a silent 16-bit mono PCM WAV file of the given length to the
    /// temporary directory and returns its URL. The caller removes it.
    static func silentWAV(seconds: Double, sampleRate: Int = 8000) throws -> URL {
        let dataSize = Int(Double(sampleRate) * seconds) * 2
        var data = Data()

        func append32(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) }
        }
        func append16(_ value: Int) {
            withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(Data("RIFF".utf8))
        append32(36 + dataSize)
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        append32(16)                // fmt chunk size
        append16(1)                 // PCM
        append16(1)                 // mono
        append32(sampleRate)
        append32(sampleRate * 2)    // byte rate
        append16(2)                 // block align
        append16(16)                // bits per sample
        data.append(Data("data".utf8))
        append32(dataSize)
        data.append(Data(count: dataSize))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("frp-silence-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }
}

@MainActor
extension XCTestCase {

    /// Spins the main run loop until `condition` holds or `timeout` passes.
    /// Main-actor hops made by the player run while it spins.
    @discardableResult
    func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// Spins the main run loop for a fixed time, to prove nothing else fires.
    func settle(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// Loads a generated file into the shared player and waits until its
    /// duration is known, so seeking is possible.
    func loadSeekableFile(autoPlay: Bool, seconds: Double = 5) throws -> URL {
        let url = try TestAudio.silentWAV(seconds: seconds)
        let player = FRadioPlayer.shared
        player.isAutoPlay = autoPlay
        player.radioURL = url
        XCTAssertTrue(waitUntil { player.duration > 0 }, "generated file must expose a duration")
        return url
    }
}
