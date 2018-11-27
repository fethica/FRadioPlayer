//
//  ViewController.swift
//  FRadioPlayer_mac
//
//  Created by Aleksandr Bobrov on 11/26/18.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Cocoa
import MediaPlayer
import FRadioPlayer

class ViewController: NSViewController {

    let player: FRadioPlayer = FRadioPlayer.shared
    // List of stations
    let stations = [Station(name: "Newport Folk Radio",
                            detail: "Are you ready to Folk?",
                            url: URL(string: "http://rfcmedia.streamguys1.com/Newport.mp3")!
                            ),

                    Station(name: "Absolute Country Hits Radio",
                            detail: "The Music Starts Here",
                            url: URL(string: "http://strm112.1.fm/acountry_mobile_mp3")!
                            ),

                    Station(name: "Chillout",
                            detail: "Your Lifestyle... Your Music!",
                            url: URL(string: "http://ic7.101.ru:8000/c15_3")!
                            )]
    
    @IBOutlet weak var stationLabel: NSTextField!
    @IBOutlet weak var artistLabel: NSTextField!
    @IBOutlet weak var trackLabel: NSTextField!
    @IBOutlet weak var artworkImage: NSImageView!
    @IBOutlet weak var statusLabel: NSTextField!
    
    @IBAction func previous(_ sender: Any) {
        selectedIndex -= 1
    }
    @IBAction func pause(_ sender: Any) {
        player.togglePlaying()
    }
    @IBAction func stop(_ sender: Any) {
        player.stop()
    }
    @IBAction func next(_ sender: Any) {
        selectedIndex += 1
    }
    // Selected station index
    var selectedIndex = 0 {
        didSet {
            defer {
                selectStation(at: selectedIndex)
                updateNowPlaying(with: track)
            }
            
            guard 0..<stations.endIndex ~= selectedIndex else {
                selectedIndex = selectedIndex < 0 ? stations.count - 1 : 0
                return
            }
        }
    }
    
    var track: Track? {
        didSet {
            artistLabel.stringValue = track?.artist ?? "none"
            trackLabel.stringValue = track?.name ?? "none"
            updateNowPlaying(with: track)
        }
    }
    
    func selectStation(at position: Int) {
        stationLabel.stringValue = stations[selectedIndex].name
        player.radioURL = stations[selectedIndex].url
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the delegate for the radio player
        player.delegate = self
        
        selectedIndex = 1
        // Show current player state
        statusLabel.stringValue = player.state.description
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func updateNowPlaying(with track: Track?) {
        
        // Define Now Playing Info
        var nowPlayingInfo = [String : Any]()
        
        if let artist = track?.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = track?.name ?? stations[selectedIndex].name
        
//        if let image = track?.image ?? stations[selectedIndex].image {
//            if #available(OSX 10.13.2, *) {
//                nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ -> NSImage in
//                    return image
//                })
//            } else {
//                // Fallback on earlier versions
//            }
//        }
//
        // Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

extension ViewController: FRadioPlayerDelegate {
    
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayerState) {
        statusLabel.stringValue = state.description
    }
    
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlaybackState) {
//        playButton.isSelected = player.isPlaying
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?) {
        track = Track(artist: artistName, name: trackName)
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?) {
        print("Raw Meta:", rawValue ?? "none")
    }
    
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
        track = nil
    }
    
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {
        
        // Please note that the following example is for demonstration purposes only, consider using asynchronous network calls to set the image from a URL.
        guard let artworkURL = artworkURL, let data = try? Data(contentsOf: artworkURL) else {
            artworkImage.image = stations[selectedIndex].image
            return
        }
        track?.image = NSImage(data: data)
        artworkImage.image = track?.image
        updateNowPlaying(with: track)
    }
}
