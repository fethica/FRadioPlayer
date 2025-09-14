//
//  FRadioPlayerObserver.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2021-10-10.
//

import Foundation


/**
 The `FRadioPlayerObserver` protocol defines methods you can implement to respond to playback events associated with an `FRadioPlayer` object.
 */
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
}
