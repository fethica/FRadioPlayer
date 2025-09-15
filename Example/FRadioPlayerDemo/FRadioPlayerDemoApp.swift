//
//  FRadioPlayerDemoApp.swift
//  FRadioPlayerDemo
//
//  Created by Urayoan Miranda on 12/3/20.
//  Copyright © 2020 FRadioPlayer Contributors. All rights reserved.
//

import SwiftUI
import MediaPlayer
import UIKit
import FRadioPlayer

@main
struct FRadioPlayerDemoApp: App {
    var radioPlayer = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(radioPlayer)
        }
    }
}

struct Radio {
    var track = Track()
    var playerState = FRadioPlayer.State.urlNotSet
    var playbackState = FRadioPlayer.PlaybackState.stopped
    var url: URL? = nil
    var rawMetadata: String? = nil
    var artworkURL: URL? = nil
    var currentStationImageName: String? = nil
}

class RadioPlayer: ObservableObject {
    
    @Published var radio = Radio()
    
    // Singleton ref to player
    let player: FRadioPlayer
    
    // List of stations
    var stations = [
        Station(name: "AZ Rock Radio",
                detail: "We Know Music from A to Z",
                url: URL(string: "http://cassini.shoutca.st:9300/stream")!,
                imageName: "station4"),
        Station(name: "The Rock FM",
                detail: "NZ's number one Rock music station.",
                url: URL(string: "https://20593.live.streamtheworld.com/CKGEFMAAC.aac")!,
                imageName: "station6"),
        Station(name: "Classic Rock",
                detail: "Your Lifestyle... Your Music!",
                url: URL(string: "https://rfcm.streamguys1.com/classicrock-mp3")!,
                imageName: "station7"),
        Station(name: "Absolute Country Hits Radio",
                detail: "The Music Starts Here",
                url: URL(string: "http://strm112.1.fm/acountry_mobile_mp3")!,
                imageName: "station1")
    ]
    
    var currentIndex = 0 {
        didSet {
            defer {
                stationDidChange(station: stations[currentIndex])
            }
            
            guard 0 ..< stations.endIndex ~= currentIndex else {
                currentIndex = currentIndex < 0 ? stations.count - 1 : 0
                return
            }
        }
    }
    
    init(player: FRadioPlayer = FRadioPlayer.shared) {
        self.player = player
        self.player.addObserver(self)
        self.player.artworkAPI = iTunesAPI(artworkSize: 500)
        self.player.isAutoPlay = true
        self.player.isPlayImmediately = false
        self.player.httpHeaderFields = ["User-Agent": "FRadioPlayerDemo/0.2.1"]
        
        setupRemoteTransportControls()
    }
    
    // - MARK: Station did Change
    
    private func stationDidChange(station: Station) {
        player.radioURL = station.url
        radio.track = Track(artist: station.detail, name: station.name)
        radio.currentStationImageName = station.imageName
        radio.artworkURL = nil
    }
}

extension RadioPlayer: FRadioPlayerObserver {
    
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
        radio.playerState = state
    }
    
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {
        radio.playbackState = state
        updateNowPlayingPlayback()
    }
    
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
        radio.url = url
        updateNowPlayingUI(with: radio)
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?) {
        
        guard let artistName = metadata?.artistName, let trackName = metadata?.trackName else {
            radio.track.name = stations[currentIndex].name
            radio.track.artist = stations[currentIndex].detail
            return
        }
        
        radio.track.artist = artistName
        radio.track.name = trackName
        updateNowPlayingUI(with: radio)
    }
    
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {
        radio.artworkURL = artworkURL
        guard let url = artworkURL else {
            setNowPlayingArtwork(nil)
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let image = UIImage(data: data)
                await MainActor.run { self.setNowPlayingArtwork(image) }
            } catch {
                await MainActor.run { self.setNowPlayingArtwork(nil) }
            }
        }
    }
}

// MARK: - Remote Controls / Lock screen

extension RadioPlayer {
    
    func setupRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Add handler for Play Command
        commandCenter.playCommand.addTarget { [unowned self] event in
            if self.player.rate == 0.0 {
                self.player.play()
                return .success
            }
            return .commandFailed
        }
        
        // Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { [unowned self] event in
            if self.player.rate == 1.0 {
                self.player.pause()
                return .success
            }
            return .commandFailed
        }
        
        // Add handler for Next Command
        commandCenter.nextTrackCommand.addTarget { [unowned self] event in
            self.currentIndex += 1
            return .success
        }
        
        // Add handler for Previous Command
        commandCenter.previousTrackCommand.addTarget { [unowned self] event in
            self.currentIndex -= 1
            return .success
        }
    }
    
    func updateNowPlayingUI(with radio: Radio) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let artist = radio.track.artist { info[MPMediaItemPropertyArtist] = artist }
        if let title = radio.track.name { info[MPMediaItemPropertyTitle] = title }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setNowPlayingArtwork(_ image: UIImage?) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let image = image {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlayback() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        // Playback rate: 1.0 when playing, 0 when paused/stopped
        let rate: Double = (radio.playbackState == .playing) ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        // Elapsed time and duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        info[MPMediaItemPropertyPlaybackDuration] = player.duration
        info[MPNowPlayingInfoPropertyIsLiveStream] = (player.duration == 0)
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
