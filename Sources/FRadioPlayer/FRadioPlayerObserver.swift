//
//  FRadioPlayerObserver.swift
//  Pods
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
     - parameter artistName: The artist name
     - parameter trackName: The track name
     */
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?)
    
    /**
     Called when player item changes the timed metadata value
     
     - parameter player: FRadioPlayer
     - parameter rawValue: metadata raw value
     */
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?)
    
    /**
     Called when the player gets the artwork for the playing song
     
     - parameter player: FRadioPlayer
     - parameter artworkURL: URL for the artwork from iTunes
     */
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?)
}


// Default empty implementations

public extension FRadioPlayerObserver {
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {}
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {}
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {}
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?) {}
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?) {}
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {}
}
