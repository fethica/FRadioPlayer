//
//  FRadioPlayerObserver.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2021-10-10.
//

import Foundation


/**
 The `FRadioPlayerObserver` protocol defines methods you can implement to respond to playback events associated with an `FRadioPlayer` object.

 Every callback is delivered on the main actor. A type that declares the
 conformance in its primary declaration becomes main-actor isolated; the
 protocol is `@preconcurrency`, so conformers written before 0.4.0 that are
 not main-actor bound keep compiling and are still called on the main thread.
 */
@preconcurrency @MainActor
public protocol FRadioPlayerObserver: AnyObject {
    
    /**
     Called when player changes state
     
     - parameter player: FRadioPlayer
     - parameter state: FRadioPlayerState
     */
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State)
    
    /**
     Called when the player changes the playing state
     
     - parameter player: FRadioPlayer
     - parameter state: FRadioPlaybackState
     */
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState)
    
    /**
     Called when player changes the current player item
     
     - parameter player: FRadioPlayer
     - parameter url: Radio URL
     */
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?)
    
    /**
     Called when player item changes the timed metadata value, it uses (separatedBy: " - ") to get the artist/song name, if you want more control over the raw metadata, consider using `metadataDidChange rawValue` instead
     
     - parameter player: FRadioPlayer
     - parameter metadata: FRadioPlayer.Metadata value
     */
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?)
    
    /**
     Called when the player gets the artwork for the playing song
     
     - parameter player: FRadioPlayer
     - parameter artworkURL: URL for the artwork from iTunes
     */
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?)
    
    /**
     Called when player item changes the duration value
     
     - parameter player: FRadioPlayer
     - parameter totalTime: player item total time, == 0 if not available (live stream)
     */
    func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval)
    
    /**
     Called when the current playing time gets changed
     
     - parameter player: FRadioPlayer
     - parameter currentTime: current time
     - parameter totalTime: player item total time
     */
    func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval)

    /**
     Called when the player starts or stops waiting for data while playback
     is wanted. The sources are exactly these:
     - `true`: `timeControlStatus` becomes `.waitingToPlayAtSpecifiedRate`,
       or the attached item's buffer runs empty, with playback wanted.
     - `false`: `timeControlStatus` becomes `.playing` or `.paused`, or
       `pause()`, `stop()` or a failure ends playback.
     `isPlaybackLikelyToKeepUp` is deliberately not a source: it is a
     prediction that can flip while audio keeps playing, and it still only
     drives the legacy `state` (`.loading` / `.loadingFinished`). Consecutive
     duplicates are not reported. Since 0.5.0.

     - parameter player: FRadioPlayer
     - parameter isBuffering: whether the player is waiting for data
     */
    func radioPlayer(_ player: FRadioPlayer, bufferingDidChange isBuffering: Bool)

    /**
     Called on every tick of the player's periodic time observer (every 0.5
     seconds while time advances), for files and live streams alike, from
     the moment an item is attached: a live stream whose duration stays
     indefinite still ticks. AVPlayer also ticks when playback starts or
     stops and on time jumps, so a tick alone does not prove audio is
     advancing: compare successive times. Samples for a discarded or
     replaced item are dropped. Meant for host watchdogs; unlike
     `playTimeDidChange` it is not deduplicated and does not change
     `currentTime`. Since 0.5.0.

     - parameter player: FRadioPlayer
     - parameter time: the current item time in seconds
     */
    func radioPlayer(_ player: FRadioPlayer, didObserveProgress time: TimeInterval)

    /**
     Called when a stall signal arrives while playback is wanted, under
     every `RecoveryPolicy`. Under `.hostManaged` this is the only reaction
     the library has: no reload is scheduled. Since 0.5.0.

     - parameter player: FRadioPlayer
     - parameter reason: the signal that was observed
     */
    func radioPlayerDidDetectStall(_ player: FRadioPlayer, reason: FRadioPlayer.StallReason)

    /**
     Called when playback fails, after playback stops and `lastFailure` is
     set, and before the `.error` state is published. Since 0.5.0.

     - parameter player: FRadioPlayer
     - parameter failure: the classified failure
     */
    func radioPlayer(_ player: FRadioPlayer, didFail failure: FRadioPlayer.Failure)

    /**
     Called when an audio session interruption ends. `shouldResume` is true
     only when the system allows resuming, playback was running when the
     interruption began, and the user did not play, pause or stop since.
     With `resumesAfterInterruption == true` (default) the player already
     resumed; with `false` resuming is the host's call. Since 0.5.0.

     - parameter player: FRadioPlayer
     - parameter shouldResume: whether resuming is warranted
     */
    func radioPlayer(_ player: FRadioPlayer, interruptionEnded shouldResume: Bool)
}


// Default empty implementations

public extension FRadioPlayerObserver {
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {}
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {}
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {}
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?) {}
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {}
    func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval) {}
    func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval) {}
    func radioPlayer(_ player: FRadioPlayer, bufferingDidChange isBuffering: Bool) {}
    func radioPlayer(_ player: FRadioPlayer, didObserveProgress time: TimeInterval) {}
    func radioPlayerDidDetectStall(_ player: FRadioPlayer, reason: FRadioPlayer.StallReason) {}
    func radioPlayer(_ player: FRadioPlayer, didFail failure: FRadioPlayer.Failure) {}
    func radioPlayer(_ player: FRadioPlayer, interruptionEnded shouldResume: Bool) {}
}
