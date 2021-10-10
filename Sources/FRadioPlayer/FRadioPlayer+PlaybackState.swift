//
//  FRadioPlaybackState.swift
//  Pods
//
//  Created by Fethi El Hassasna on 2021-10-10.
//

import Foundation


public extension FRadioPlayer {
    
    /**
     `FRadioPlayingState` is the Player playing state enum
     */
    enum PlaybackState: Int {
        
        /// Player is playing
        case playing
        
        /// Player is paused
        case paused
        
        /// Player is stopped
        case stopped
        
        /// Return a readable description
        public var description: String {
            switch self {
            case .playing: return "Player is playing"
            case .paused: return "Player is paused"
            case .stopped: return "Player is stopped"
            }
        }
    }
}
