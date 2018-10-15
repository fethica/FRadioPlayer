//
//  ViewController.swift
//  FRadioPlayerDemo
//
//  Created by Fethi El Hassasna on 2017-11-11.
//  Copyright © 2017 Fethi El Hassasna. All rights reserved.
//

import UIKit
import MediaPlayer
import FRadioPlayer

class ViewController: UIViewController {
    
    // IB UI
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var trackLabel: UILabel!
    @IBOutlet weak var infoContainer: UIView!
    @IBOutlet weak var timeContainer: UIView!
    @IBOutlet weak var artworkImageView: UIImageView!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var totalTimeLabel: UILabel!
    @IBOutlet weak var timeSlider: UISlider!
    
    // Singleton ref to player
    let player: FRadioPlayer = FRadioPlayer.shared
    
    // List of stations
    let stations = [Station(name: "Newport Folk Radio",
                            detail: "Are you ready to Folk?",
                            url: URL(string: "http://rfcmedia.streamguys1.com/Newport.mp3")!,
                            image: #imageLiteral(resourceName: "station2")),
                    
                    Station(name: "Absolute Country Hits Radio",
                            detail: "The Music Starts Here",
                            url: URL(string: "http://strm112.1.fm/acountry_mobile_mp3")!,
                            image: #imageLiteral(resourceName: "station1")),
                    
                    Station(name: "Sample Audio File",
                            detail: "mp3, 45 seconds",
                            url: URL(string: "https://www.sample-videos.com/audio/mp3/wave.mp3")!,
                            image: #imageLiteral(resourceName: "audiofile"))]
    
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
            artistLabel.text = track?.artist
            trackLabel.text = track?.name
            updateNowPlaying(with: track)
        }
    }
    
    var isSliderSliding = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "FRadioPlayer"
        
        // Set the delegate for the radio player
        player.delegate = self
        
        // Show current player state
        statusLabel.text = player.state.description
        
        tableView.tableFooterView = UIView()
        infoContainer.isHidden = true
        timeContainer.isHidden = true
        
        setupRemoteTransportControls()
        
        // Could be added using IB
        timeSlider.addTarget(self, action: #selector(timeSliderTouchBegan(sender:)), for: .touchDown)
        timeSlider.addTarget(self, action: #selector(timeSliderValueChanged(sender:)), for: .valueChanged)
        timeSlider.addTarget(self, action: #selector(timeSliderTouchEnded(sender:)), for: [.touchUpInside, .touchCancel, .touchUpOutside])
    }
    
    // MARK: - Actions
    
    @IBAction func playTap(_ sender: Any) {
        player.togglePlaying()
    }
    
    @IBAction func stopTap(_ sender: Any) {
        player.stop()
    }
    
    @IBAction func previousTap(_ sender: Any) {
        previous()
    }
    
    @IBAction func nextTap(_ sender: Any) {
        next()
    }
    
    @objc func timeSliderTouchBegan(sender: UISlider) {
        handleTimeSlider(slider: sender, event: .touchDown)
    }
    
    @objc func timeSliderValueChanged(sender: UISlider) {
        handleTimeSlider(slider: sender, event: .valueChanged)
    }
    
    @objc func timeSliderTouchEnded(sender: UISlider) {
        handleTimeSlider(slider: sender, event: .touchUpInside)
    }
    
    // MARK: - Methods
    
    func handleTimeSlider(slider: UISlider, event: UIControl.Event) {
        
        guard !player.isLiveStream else { return }
        
        let seekTime =  TimeInterval(slider.value) * player.duration
        
        switch event {
        case .valueChanged:
            currentTimeLabel.text = formatSecondsToString(seekTime)
            totalTimeLabel.text = formatSecondsToString(player.duration - seekTime)
            
        case .touchDown:
            isSliderSliding = true
            
        case .touchUpInside:
            player.seek(to: seekTime, completion: {
                self.isSliderSliding = false
            })
            
        default:
            break
        }
        
    }
    
    func next() {
        selectedIndex += 1
    }
    
    func previous() {
        selectedIndex -= 1
    }
    
    func selectStation(at position: Int) {
        player.radioURL = stations[selectedIndex].url
        tableView.selectRow(at: IndexPath(item: position, section: 0), animated: true, scrollPosition: .none)
    }
    
    // MARK: - Helpers
    
    func resetTimeContainer() {
        timeSlider.value = 0
        currentTimeLabel.text = "00:00"
        totalTimeLabel.text = "00:00"
    }
    
    func formatSecondsToString(_ secounds: TimeInterval) -> String {
        guard secounds != 0 else { return "00:00" }
        
        let min = Int(secounds / 60)
        let sec = Int(secounds.truncatingRemainder(dividingBy: 60))
        
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - FRadioPlayerDelegate

extension ViewController: FRadioPlayerDelegate {
    
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayerState) {
        statusLabel.text = state.description
    }
    
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlaybackState) {
        playButton.isSelected = player.isPlaying
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?) {
        track = Track(artist: artistName, name: trackName)
    }
    
    func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?) {
        track = nil
        
    }
    
    func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?) {
        infoContainer.isHidden = (rawValue == nil)
    }
    
    func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?) {
        
        // Please note that the following example is for demonstration purposes only, consider using asynchronous network calls to set the image from a URL.
        guard let artworkURL = artworkURL, let data = try? Data(contentsOf: artworkURL) else {
            artworkImageView.image = stations[selectedIndex].image
            return
        }
        track?.image = UIImage(data: data)
        artworkImageView.image = track?.image
        updateNowPlaying(with: track)
    }
    
    func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval) {
        if player.isLiveStream {
            resetTimeContainer()
            timeContainer.isHidden = true
            timeSlider.isEnabled = false
        } else {
            timeContainer.isHidden = false
            timeSlider.isEnabled = true
            totalTimeLabel.text = formatSecondsToString(duration)
        }
    }
    
    func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval) {
        guard !isSliderSliding else { return }
        
        currentTimeLabel.text = formatSecondsToString(currentTime)
        timeSlider.value = Float(currentTime / duration)
        totalTimeLabel.text = formatSecondsToString(duration - currentTime)
    }
}

// MARK: - UITableViewDelegate

extension ViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return stations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = stations[indexPath.item].name
        cell.detailTextLabel?.text = stations[indexPath.item].detail
        cell.imageView?.image = stations[indexPath.item].image
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndex = indexPath.item
    }
}

// MARK: - Remote Controls / Lock screen

extension ViewController {
    
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
            self.next()
            return .success
        }
        
        // Add handler for Previous Command
        commandCenter.previousTrackCommand.addTarget { [unowned self] event in
            self.previous()
            return .success
        }
    }
    
    func updateNowPlaying(with track: Track?) {
    
        // Define Now Playing Info
        var nowPlayingInfo = [String : Any]()
        
        if let artist = track?.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = track?.name ?? stations[selectedIndex].name
        
        if let image = track?.image ?? stations[selectedIndex].image {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ -> UIImage in
                return image
            })
        }
        
        // Set the metadata
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

// MARK: - UINavigationController

extension UINavigationController {
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
