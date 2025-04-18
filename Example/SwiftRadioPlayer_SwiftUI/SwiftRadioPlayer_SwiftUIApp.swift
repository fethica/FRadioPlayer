//
//  SwiftRadioPlayer_SwiftUIApp.swift
//  SwiftRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/3/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import SwiftRadioPlayer

@main
struct SwiftRadioPlayer_SwiftUIApp: App {
    var radioPlayer = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(radioPlayer)
        }
    }
}

struct Radio {
    var track = Track()
    var playerState = SwiftRadioPlayerState.urlNotSet
    var playbackState = FRadioPlaybackState.stopped
    var url: URL? = nil
    var rawMetadata: String? = nil
}

class RadioPlayer: SwiftRadioPlayerDelegate, ObservableObject {
    
    @Published var radio = Radio()
    
    // Singleton ref to player
    var player: SwiftRadioPlayer = SwiftRadioPlayer.shared
    
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
    
    init() {
        player.delegate = self
        player.artworkSize = 500
        player.isAutoPlay = true
    }
    
    func radioPlayer(_ player: SwiftRadioPlayer, playerStateDidChange state: SwiftRadioPlayerState) {
        radio.playerState = state
    }
    
    func radioPlayer(_ player: SwiftRadioPlayer, playbackStateDidChange state: FRadioPlaybackState) {
        radio.playbackState = state
    }
    
    func radioPlayer(_ player: SwiftRadioPlayer, metadataDidChange artistName: String?, trackName: String?) {
        guard let artistName = artistName, let trackName = trackName else {
            radio.track.name = stations[currentIndex].name
            radio.track.artist = stations[currentIndex].detail
            return
        }
        
        radio.track.artist = artistName
        radio.track.name = trackName
    }
    
    func radioPlayer(_ player: SwiftRadioPlayer, itemDidChange url: URL?) {
        radio.url = url
    }
    
    func radioPlayer(_ player: SwiftRadioPlayer, metadataDidChange rawValue: String?) {
        radio.rawMetadata = rawValue
    }
    
    func radioPlayer(_ player: SwiftRadioPlayer, artworkDidChange artworkURL: URL?) {
        // Please note that the following example is for demonstration purposes only, consider using asynchronous network calls to set the image from a URL.
        guard let artworkURL = artworkURL, let data = try? Data(contentsOf: artworkURL) else {
            radio.track.image = stations[currentIndex].image
            return
        }
        
        radio.track.image = UIImage(data: data)
    }
    
    // - MARK: Station did Change
    
    private func stationDidChange(station: Station) {
        player.radioURL = station.url
        radio.track = Track(artist: station.detail, name: station.name, image: station.image)
    }
}
