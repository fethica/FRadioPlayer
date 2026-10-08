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
    /// Live connections and whether stop() ran. Registration, pruning
    /// and shutdown all run on `queue`; the lock only makes the state
    /// Sendable for the closures that capture it.
    private struct State {
        var connections: [NWConnection] = []
        var stopped = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Starts listening on an ephemeral loopback port
    init() throws {
        let chunk = try Self.silentAAC(seconds: 2)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)

        let queue = self.queue
        let state = self.state
        listener.newConnectionHandler = { connection in
            // Runs on `queue`, like stop(): a connection arriving after
            // stop() is cancelled instead of registered
            let accepted = state.withLock { state -> Bool in
                guard !state.stopped else { return false }
                state.connections.append(connection)
                return true
            }
            guard accepted else { connection.cancel(); return }
            connection.stateUpdateHandler = { update in
                switch update {
                case .cancelled, .failed:
                    state.withLock { $0.connections.removeAll { $0 === connection } }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            // Any request gets the endless response
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                let header = "HTTP/1.0 200 OK\r\nContent-Type: audio/aac\r\nCache-Control: no-cache\r\n\r\n"
                connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
                Self.pump(chunk, to: connection, on: queue, state: state)
            }
        }
        listener.start(queue: queue)
    }

    /// The stream URL, once the listener is ready (nil before)
    var url: URL? {
        guard let port = listener.port, port.rawValue != 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/live.aac")
    }

    /// Stops listening and cancels every connection, serialized with
    /// connection registration on the listener queue. Call it from any
    /// queue but that one.
    func stop() {
        queue.sync {
            let open = state.withLock { state -> [NWConnection] in
                state.stopped = true
                defer { state.connections.removeAll() }
                return state.connections
            }
            listener.cancel()
            open.forEach { $0.cancel() }
        }
    }

    /// Sends 2 s of audio every 1.5 s, slightly ahead of real time, until
    /// the connection goes away or the stream stops
    private static func pump(_ chunk: Data, to connection: NWConnection, on queue: DispatchQueue,
                             state: OSAllocatedUnfairLock<State>) {
        guard !state.withLock({ $0.stopped }) else { return }
        connection.send(content: chunk, completion: .contentProcessed { error in
            guard error == nil else { return }
            queue.asyncAfter(deadline: .now() + 1.5) { pump(chunk, to: connection, on: queue, state: state) }
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
