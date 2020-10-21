//
//  FRadioPlayer.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2017-11-11.
//  Copyright © 2017 Fethi El Hassasna (@fethica). All rights reserved.
//

import AVFoundation

// MARK: - FRadioPlayingState

/**
 `FRadioPlayingState` is the Player playing state enum
 */

@objc public enum FRadioPlaybackState: Int {
    
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

// MARK: - FRadioPlayerState

/**
 `FRadioPlayerState` is the Player status enum
 */

@objc public enum FRadioPlayerState: Int {
    
    /// URL not set
    case urlNotSet

    /// URL set but not loaded yet
    case urlNotLoaded
    
    /// Player is ready to play
    case readyToPlay
    
    /// Player is loading
    case loading
    
    /// The loading has finished
    case loadingFinished
    
    /// Error with playing
    case error
    
    /// Return a readable description
    public var description: String {
        switch self {
        case .urlNotSet: return "URL is not set"
        case .urlNotLoaded: return "URL is set but not loaded yet"
        case .readyToPlay: return "Ready to play"
        case .loading: return "Loading"
        case .loadingFinished: return "Loading finished"
        case .error: return "Error"
        }
    }
}

// MARK: - FRadioPlayerDelegate

/**
 The `FRadioPlayerDelegate` protocol defines methods you can implement to respond to playback events associated with an `FRadioPlayer` object.
 */

@objc public protocol FRadioPlayerDelegate: class {
    /**
     Called when player changes state
     
     - parameter player: FRadioPlayer
     - parameter state: FRadioPlayerState
     */
    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayerState)
    
    /**
     Called when the player changes the playing state
     
     - parameter player: FRadioPlayer
     - parameter state: FRadioPlaybackState
     */
    func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlaybackState)
    
    /**
     Called when player changes the current player item
     
     - parameter player: FRadioPlayer
     - parameter url: Radio URL
     */
    @objc optional func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?)
    
    /**
     Called when player item changes the timed metadata value, it uses (separatedBy: " - ") to get the artist/song name, if you want more control over the raw metadata, consider using `metadataDidChange rawValue` instead
     
     - parameter player: FRadioPlayer
     - parameter artistName: The artist name
     - parameter trackName: The track name
     */
    @objc optional func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?)
    
    /**
     Called when player item changes the timed metadata value
     
     - parameter player: FRadioPlayer
     - parameter rawValue: metadata raw value
     */
    @objc optional func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?)
    
    /**
     Called when the player gets the artwork for the playing song
     
     - parameter player: FRadioPlayer
     - parameter artworkURL: URL for the artwork from iTunes
     */
    @objc optional func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?)
    
    /**
     Called when player item changes the duration value
     
     - parameter player: FRadioPlayer
     - parameter totalTime: player item total time, == 0 if not available (live stream)
     */
    @objc optional func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval)
    
    /**
     Called when the current playing time gets changed
     
     - parameter player: FRadioPlayer
     - parameter currentTime: current time
     - parameter totalTime: player item total time
     */
    @objc optional func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval)
}

// MARK: - FRadioPlayer

/**
 FRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.
 */

open class FRadioPlayer: NSObject {
    
    // MARK: - Properties
    
    /// Returns the singleton `FRadioPlayer` instance.
    public static let shared = FRadioPlayer()
    
    /**
     The delegate object for the `FRadioPlayer`.
     Implement the methods declared by the `FRadioPlayerDelegate` object to respond to user interactions and the player output.
     */
    open weak var delegate: FRadioPlayerDelegate?
    
    /// The player current radio URL
    open var radioURL: URL? {
        didSet {
            radioURLDidChange(with: radioURL)
        }
    }
    
    /// The player starts playing when the radioURL property gets set. (default == true)
    open var isAutoPlay = true
    
    /// Enable fetching albums artwork from the iTunes API. (default == true)
    open var enableArtwork = true
    
    /// Artwork image size. (default == 100 | 100x100)
    open var artworkSize = 100
    
    /// Read only property to get the current AVPlayer rate.
    open var rate: Float? {
        return player.rate
    }
    
    /// Check if the player is playing
    open var isPlaying: Bool {
        switch playbackState {
        case .playing:
            return true
        case .stopped, .paused:
            return false
        }
    }
    
    /// Check if the item is live stream or audio file
    open var isLiveStream: Bool {
        return duration == 0
    }
    
    /// Player current state of type `FRadioPlayerState`
    open private(set) var state = FRadioPlayerState.urlNotSet {
        didSet {
            guard oldValue != state else { return }
            delegate?.radioPlayer(self, playerStateDidChange: state)
        }
    }
    
    /// Playing state of type `FRadioPlaybackState`
    open private(set) var playbackState = FRadioPlaybackState.stopped {
        didSet {
            guard oldValue != playbackState else { return }
            delegate?.radioPlayer(self, playbackStateDidChange: playbackState)
        }
    }
    
    /// Store the item duration, == 0 if not available
    open private(set) var duration: TimeInterval = 0 {
        didSet {
            guard oldValue != duration else { return }
            delegate?.radioPlayer?(self, durationDidChange: duration)
        }
    }
    
    /// Store the current time, == 0 if not available
    open private(set) var currentTime: Double = 0 {
        didSet {
            guard oldValue != currentTime else { return }
            delegate?.radioPlayer?(self, playTimeDidChange: currentTime, duration: duration)
        }
    }
    
    // MARK: - Private properties
    
    /// AVPlayer
    private var player: AVPlayer
    
    /// Last player item
    private var lastPlayerItem: AVPlayerItem?
    
    /// Check for headphones, used to handle audio route change
    private var headphonesConnected: Bool = false
    
    /// Default player item
    private var playerItem: AVPlayerItem?
    
    /// Reachability for network interruption handling
    private let reachability = Reachability()!
    
    /// Current network connectivity
    private var isConnected = false
    
    /// Player time observer
    private var timeObserver: Any?
    
    /// Item played to the end
    private var isPlayedToEndTime = false
    
    // MARK: - Initialization
    
    private init(player: AVPlayer = AVPlayer()) {
        self.player = player
        super.init()
        
        // Enable bluetooth playback
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode.default, options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay])
        
        // Notifications
        setupNotifications()
        
        // Check for headphones
        checkHeadphonesConnection(outputs: AVAudioSession.sharedInstance().currentRoute.outputs)
        
        // Reachability config
        try? reachability.startNotifier()
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        isConnected = reachability.connection != .none

        self.player.allowsExternalPlayback = false
    }
    
    // MARK: - Control Methods
    
    /**
     Triggers the play function of the radio player
     
     */
    open func play() {

        guard playerItem != nil else {
            setupPlayer()
            return
        }

        if player.currentItem == nil {
            player.replaceCurrentItem(with: playerItem)
        }
        
        player.play()
        playbackState = .playing
    }
    
    /**
    Triggers the play immediately function of the radio player
    
    */
    open func playImmediately() {
        guard playerItem != nil else {
            setupPlayer()
            return
        }

        if player.currentItem == nil {
            player.replaceCurrentItem(with: playerItem)
        }
        player.playImmediately(atRate: self.rate ?? 1.0)
        playbackState = .playing
    }
    
    /**
     Triggers the pause function of the radio player
     
     */
    open func pause() {
        // TODO: Check for playability
        player.pause()
        playbackState = .paused
    }
    
    /**
     Triggers the stop function of the radio player
     
     */
    open func stop() {
        // TODO: Check for playability

        if duration != 0 {
            currentTime = 0
            player.pause()
            player.seek(to: .zero)
        } else {
            player.replaceCurrentItem(with: nil)
            timedMetadataDidChange(rawValue: nil)
        }
        
        playbackState = .stopped
    }
    
    /**
     Triggers the seek to a given time
     
     - parameter seconds: time in seconds to seek to
     - parameter completion: optional completion
     */
    open func seek(to seconds: TimeInterval, completion: (()->())?) {
        guard duration != 0 else { return }
        
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 1)
        
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .positiveInfinity, completionHandler: { _ in
            self.play()
            completion?()
        })
    }
    
    /**
     Toggles isPlaying state
     
     */
    open func togglePlaying() {
        isPlaying ? pause() : play()
    }
    
    /**
    Toggles isPlaying state (play immediately)
    
    */
    open func togglePlayingImmediately() {
        isPlaying ? pause() : playImmediately()
    }
    

    private var asset: AVAsset? = nil
    
    // MARK: - Private helpers
    
    private func radioURLDidChange(with url: URL?) {
        resetPlayer()
        delegate?.radioPlayer?(self, itemDidChange: radioURL)

        guard let url = url else { state = .urlNotSet; return }

        state = .urlNotLoaded
        asset = AVAsset(url: url)

        guard isAutoPlay else { return }
        
        setupPlayer()
    }
    
    private func setupPlayer() {
        guard let asset = asset else { return }
        state = .loading
        playerItem = AVPlayerItem(asset: asset)
        playerItemDidChange()
    }
    
    /** Reset all player item observers and create new ones
     
     */
    private func playerItemDidChange() {
        
        guard lastPlayerItem != playerItem else { return }
        
        if let item = lastPlayerItem {
            pause()
            
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            item.removeObserver(self, forKeyPath: "status")
            item.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
            item.removeObserver(self, forKeyPath: "timedMetadata")
            item.removeObserver(self, forKeyPath: "duration")
        }
        
        lastPlayerItem = playerItem
        timedMetadataDidChange(rawValue: nil)
        durationDidChange(.zero)
        
        if let item = playerItem {
            NotificationCenter.default.addObserver(self, selector: #selector(itemDidPlayToEnd), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            item.addObserver(self, forKeyPath: "status", options: .new, context: nil)
            item.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
            item.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
            item.addObserver(self, forKeyPath: "timedMetadata", options: .new, context: nil)
            item.addObserver(self, forKeyPath: "duration", options: .new, context: nil)

            play()
        }
    }
    
    private func timedMetadataDidChange(rawValue: String?) {
        let parts = rawValue?.components(separatedBy: " - ")
        delegate?.radioPlayer?(self, metadataDidChange: parts?.first, trackName: parts?.last)
        delegate?.radioPlayer?(self, metadataDidChange: rawValue)
        shouldGetArtwork(for: rawValue, enableArtwork)
    }
    
    private func shouldGetArtwork(for rawValue: String?, _ enabled: Bool) {
        guard enabled else { return }
        guard let rawValue = rawValue else {
            self.delegate?.radioPlayer?(self, artworkDidChange: nil)
            return
        }
        
        FRadioAPI.getArtwork(for: rawValue, size: artworkSize, completionHandler: { [unowned self] artworlURL in
            DispatchQueue.main.async {
                self.delegate?.radioPlayer?(self, artworkDidChange: artworlURL)
            }
        })
    }

    private func reloadItem() {
        guard let url = radioURL else { return }
        asset = AVAsset(url: url)
        guard let asset = asset else { return }
        playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: nil)
        player.replaceCurrentItem(with: playerItem)
    }
    
    private func resetPlayer() {
        stop()
        asset?.cancelLoading()
        asset = nil
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        lastPlayerItem = nil
        duration = 0
        currentTime = 0
        
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
    
    deinit {
        resetPlayer()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    // MARK: - Responding to Interruptions
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }
        
        switch type {
        case .began:
            DispatchQueue.main.async { self.pause() }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { break }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            DispatchQueue.main.async { options.contains(.shouldResume) ? self.play() : self.pause() }
        }
    }
    
    @objc private func reachabilityChanged(note: Notification) {
        
        guard let reachability = note.object as? Reachability else { return }
        
        // Check if the internet connection was lost
        if reachability.connection != .none, !isConnected {
            checkNetworkInterruption()
        }
        
        isConnected = reachability.connection != .none
    }
    
    // Check if the playback could keep up after a network interruption
    private func checkNetworkInterruption() {
        guard
            let item = playerItem,
            !item.isPlaybackLikelyToKeepUp,
            reachability.connection != .none else { return }

        if isLiveStream {
            player.replaceCurrentItem(with: nil)
        } else {
            player.pause()
        }
        
        // Wait 1 sec to recheck and make sure the reload is needed
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            if !item.isPlaybackLikelyToKeepUp, self.player.currentItem == nil { self.reloadItem() }
            
            if self.isPlaying {
                self.play()
            } else {
                self.isLiveStream ? self.stop() : self.pause()
            }
        }
    }
    
    // MARK: - Responding to Route Changes
    
    private func checkHeadphonesConnection(outputs: [AVAudioSessionPortDescription]) {
        for output in outputs where output.portType == .headphones {
            headphonesConnected = true
            break
        }
        headphonesConnected = false
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else { return }
        
        switch reason {
        case .newDeviceAvailable:
            checkHeadphonesConnection(outputs: AVAudioSession.sharedInstance().currentRoute.outputs)
        case .oldDeviceUnavailable:
            guard let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
            checkHeadphonesConnection(outputs: previousRoute.outputs);
            DispatchQueue.main.async { self.headphonesConnected ? () : self.pause() }
        default: break
        }
    }
    
    // MARK: - KVO
    
    /// :nodoc:
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if let item = object as? AVPlayerItem, let keyPath = keyPath, item == self.playerItem {
            
            switch keyPath {
                
            case "status":
                
                if player.status == AVPlayer.Status.readyToPlay {
                    self.state = .readyToPlay
                } else if player.status == AVPlayer.Status.failed {
                    self.state = .error
                }
                
            case "playbackBufferEmpty":
                
                if item.isPlaybackBufferEmpty {
                    self.state = .loading
                    self.checkNetworkInterruption()
                }
                
            case "playbackLikelyToKeepUp":
                
                self.state = item.isPlaybackLikelyToKeepUp ? .loadingFinished : .loading
            
            case "timedMetadata":
                let rawValue = item.timedMetadata?.first?.value as? String
                timedMetadataDidChange(rawValue: rawValue)
            
            case "duration":
                durationDidChange(item.duration)
                
            default:
                break
            }
        }
    }
}

// MARK: - Audio file support

extension FRadioPlayer {
    
    private func periodicTimeUpdate(_ time: CMTime) {
        guard !isPlayedToEndTime else { return }
        let playedTime = CMTimeGetSeconds(time)
        currentTime = playedTime
    }
    
    @objc private func itemDidPlayToEnd() {
        // tODO:
        pause()
        isPlayedToEndTime = true
        
        player.seek(to: .zero) { [weak self] _ in
            self?.isPlayedToEndTime = false
        }
    }
    
    private func durationDidChange(_ duration: CMTime) {
        
        if CMTIME_IS_INDEFINITE(duration) || duration == .zero {
            // Live stream
            self.duration = 0
            
            if let timeObserver = self.timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            
        } else {
            // Audio file
            self.duration = Double(CMTimeGetSeconds(duration))
            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] time in
                self?.periodicTimeUpdate(time)
            })
        }
    }
}
