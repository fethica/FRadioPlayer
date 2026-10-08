//
//  FRadioPlayer+Recovery.swift
//  FRadioPlayer
//
//  Host seams for stall recovery: who owns the reload ladder, and the
//  signals a host watchdog needs when it owns it.
//

import Foundation

public extension FRadioPlayer {

    /// Who recovers a stalled stream.
    enum RecoveryPolicy: Sendable {

        /// The library's built-in ladder (reload after 2, 4 and 8 seconds
        /// of a mid-playback stall, then `.error`). The 0.4.0 behaviour.
        case automatic

        /// The library never schedules a reload. Stall, buffering and
        /// progress signals are reported to observers and the host decides
        /// when to retry, typically with `stop(discardingItem: true)`
        /// followed by `play()`.
        case hostManaged
    }

    /// The signal behind `radioPlayerDidDetectStall(_:reason:)`.
    enum StallReason: Sendable {

        /// The current item's playback buffer ran empty while playback was
        /// wanted.
        case bufferEmpty

        /// The network path came back while playback was wanted.
        case networkReconnected

        /// AVFoundation posted `AVPlayerItemPlaybackStalled` for the
        /// current item while playback was wanted.
        case playbackStalledNotification
    }
}
