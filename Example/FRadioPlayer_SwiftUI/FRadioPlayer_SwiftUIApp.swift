//
//  FRadioPlayer_SwiftUIApp.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/3/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import FRadioPlayer

@main
struct FRadioPlayer_SwiftUIApp: App {
    var state = RadioDelegateClass()
    
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state)
        }
    }
}

class RadioDelegateClass: FRadioPlayerDelegate, ObservableObject {
    
    @Published var radioPlayerShared    = FRadioPlayer.shared
    @Published var metadata             = Track()
    @Published var artist               = "Not Playing"
    @Published var name                 = ""
    @Published var playbackImage        = "play.fill"
    //@Published var artworkImageView     = UIImage(named: "albumArt50")
    
    //MARK: another way to make it @Published but with more control. Is the same as (next line)
    //@Published var artworkImageView = UIImage(named: "albumArt50")
    var artworkImageView = UIImage(named: "albumArt") {
        willSet {
            print("Just published artworkImageView value")
            objectWillChange.send()
        }
    }
    
    // Singleton ref to player
    @Published var player: FRadioPlayer = FRadioPlayer.shared
    
    // List of stations
    @Published var stations = [Station(name: "AZ Rock Radio",
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
                                       image:#imageLiteral(resourceName: "albumArt")),
                               
                               Station(name: "Newport Folk Radio",
                                       detail: "Are you ready to Folk?",
                                       url: URL(string: "http:rfcmedia.streamguys1.com/Newport.mp3")!,
                                       image: #imageLiteral(resourceName: "station2")),
                               
                               Station(name: "Absolute Country Hits Radio",
                                       detail: "The Music Starts Here",
                                       url: URL(string: "http:strm112.1.fm/acountry_mobile_mp3")!,
                                       image: #imageLiteral(resourceName: "station1")),
                               
                               Station(name: "The Alt Vault",
                                       detail: "Your Lifestyle... Your Music!",
                                       url: URL(string: "http:jupiter.prostreaming.net/altmixxlow")!,
                                       image: #imageLiteral(resourceName: "station3"))]
    
    var currentIndex = 0 {
        didSet {
            print("Did set cuurentIndex to \(currentIndex)")
            defer {
                stationDidChange(station: stations[currentIndex])
            }
            
            guard 0..<stations.endIndex ~= currentIndex else {
                currentIndex = currentIndex < 0 ? stations.count - 1 : 0
                return
            }
        }
        willSet {
            //MARK: To make the object Published
            print("Just Published the currentIndex value")
            objectWillChange.send()
        }
    }
    
    init() {
        player.delegate     = self
        player.artworkSize  = 100
    }
    
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayerState) {
        print("playerStateDidChange \(player.isPlaying)")
        artist = state.description
    }
    
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlaybackState) {
        print("playbackStateDidChange \(player.isPlaying)")
        if player.isPlaying {
            playbackImage = "pause.fill"
        } else {
            playbackImage = "play.fill"
        }
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?) {
        print("Metadata Did Change")
        artist  = artistName ?? "No Metadata"
        name    = trackName ?? ""
    }
    
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
        print("Item did change")
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?) {
        print("Metadata did change - raw value")
    }
    
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {
        print("Artwork Did Change")
        // Please note that the following example is for demonstration purposes only, consider using asynchronous network calls to set the image from a URL.
        guard let artworkURL = artworkURL, let data = try? Data(contentsOf: artworkURL) else {
            artworkImageView = UIImage(named: "albumArt")
            return
        }
        metadata.image  = UIImage(data: data)
    }
    
    //MARK: Station Did Change
    func stationDidChange(station: Station) {
        print("Station Did Change")
        print("Current Index: \(currentIndex)")
        radioPlayerShared.radioURL = station.url
        radioPlayerShared.play()
    }
}
