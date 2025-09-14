//
//  FRadioPlayer_SwiftUIApp.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/3/20.
//  Copyright © 2020 FRadioPlayer Contributors. All rights reserved.
//

import SwiftUI
import MediaPlayer
import FRadioPlayer

@main
struct FRadioPlayer_SwiftUIApp: App {
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
}

class RadioPlayer: ObservableObject {
    
    @Published var radio = Radio()
    
    // Singleton ref to player
    let player: FRadioPlayer
    
    // List of stations
    var stations = [Station(name: "AZ Rock Radio",
                            detail: "We Know Music from A to Z",
                            url: URL(string: "http://cassini.shoutca.st:9300/stream")!,
                            image: #imageLiteral(resourceName: "station4")),
                    
                    Station(name: "Metal PR",
                            detail: "El Lechón Atómico",
                            url: URL(string: "http://199.195.194.140:8026/live")!,
                            image: #imageLiteral(resourceName: "station5")),
                    
                    Station(name: "Chillout",
                            detail: "Your Lifestyle... Your Music!",
                            url: URL(string: "http://ic7.101.ru:8000/c15_3")!,
                            image: #imageLiteral(resourceName: "albumArt")),
                    
                    Station(name: "Absolute Country Hits Radio",
                            detail: "The Music Starts Here",
                            url: URL(string: "http:strm112.1.fm/acountry_mobile_mp3")!,
                            image: #imageLiteral(resourceName: "station1"))]
    
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
        
        setupRemoteTransportControls()
    }
    
    // - MARK: Station did Change
    
    private func stationDidChange(station: Station) {
        player.radioURL = station.url
        radio.track = Track(artist: station.detail, name: station.name, image: station.image)
    }
}

extension RadioPlayer: FRadioPlayerObserver {
    
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
        radio.playerState = state
    }
    
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState) {
        radio.playbackState = state
    }
    
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
        radio.url = url
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?) {
        
        guard let artistName = metadata?.artistName, let trackName = metadata?.trackName else {
            radio.track.name = stations[currentIndex].name
            radio.track.artist = stations[currentIndex].detail
            return
        }
        
        radio.track.artist = artistName
        radio.track.name = trackName
    }
    
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {
        // Please note that the following example is for demonstration purposes only, consider using asynchronous network calls to set the image from a URL.
        guard let artworkURL = artworkURL, let data = try? Data(contentsOf: artworkURL), let image = UIImage(data: data) else {
            radio.track.image = stations[currentIndex].image
            return
        }
        
        radio.track.image = image
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
        
        // Now Playing Info
        var nowPlayingInfo = [String : Any]()
        
        if let artist = radio.track.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = radio.track.name
        
        if let image = radio.track.image {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ -> UIImage in
                return image
            })
        }
        
        // Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
