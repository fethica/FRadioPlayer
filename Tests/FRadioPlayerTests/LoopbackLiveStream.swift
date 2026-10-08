//
//  LoopbackLiveStream.swift
//  FRadioPlayerTests
//
//  A live radio stand-in on 127.0.0.1: an HTTP/1.0 response with no
//  Content-Length that keeps sending ADTS AAC silence, like a Shoutcast or
//  Icecast mount. AVPlayer reports its duration as indefinite for as long
//  as it plays, so the live code paths run without injected durations.
//

import AVFoundation
import Network
import os

final class LoopbackLiveStream: Sendable {

    private let listener: NWListener
    private let queue = DispatchQueue(label: "FRadioPlayerTests.LoopbackLiveStream")
    private let connections = OSAllocatedUnfairLock<[NWConnection]>(initialState: [])

    /// Starts listening on an ephemeral loopback port
    init() throws {
        let chunk = try Self.silentAAC(seconds: 2)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)

        let queue = self.queue
        let connections = self.connections
        listener.newConnectionHandler = { connection in
            connections.withLock { $0.append(connection) }
            connection.start(queue: queue)
            // Any request gets the endless response
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                let header = "HTTP/1.0 200 OK\r\nContent-Type: audio/aac\r\nCache-Control: no-cache\r\n\r\n"
                connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
                Self.pump(chunk, to: connection, on: queue)
            }
        }
        listener.start(queue: queue)
    }

    /// The stream URL, once the listener is ready (nil before)
    var url: URL? {
        guard let port = listener.port, port.rawValue != 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/live.aac")
    }

    func stop() {
        listener.cancel()
        connections.withLock { list in
            list.forEach { $0.cancel() }
            list.removeAll()
        }
    }

    /// Sends 2 s of audio every 1.5 s, slightly ahead of real time, until
    /// the connection goes away
    private static func pump(_ chunk: Data, to connection: NWConnection, on queue: DispatchQueue) {
        connection.send(content: chunk, completion: .contentProcessed { error in
            guard error == nil else { return }
            queue.asyncAfter(deadline: .now() + 1.5) { pump(chunk, to: connection, on: queue) }
        })
    }

    /// Encodes silence to an ADTS AAC file (the .aac extension selects
    /// ADTS) and returns its bytes. Concatenated ADTS frames stay valid.
    private static func silentAAC(seconds: Double) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("frp-live-\(UUID().uuidString).aac")
        defer { try? FileManager.default.removeItem(at: url) }
        let sampleRate = 44_100.0
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let frames = AVAudioFrameCount(sampleRate * seconds)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
                throw CocoaError(.fileWriteUnknown)
            }
            buffer.frameLength = frames
            try file.write(from: buffer)
        } // the file is flushed when it goes out of scope
        return try Data(contentsOf: url)
    }
}
