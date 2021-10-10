//
//  FRadioPlayer.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2017-11-11.
//  Copyright © 2017 Fethi El Hassasna (@fethica). All rights reserved.
//

import AVFoundation

/**
 FRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.
 */

open class FRadioPlayer: NSObject {
    
    // MARK: - Properties
    
    /// Returns the singleton `FRadioPlayer` instance.
    public static let shared = FRadioPlayer()
    
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
    
    /// HTTP headers for AVURLAsset (Ex: `["user-agent": "FRadioPlayer"]`).
    open var httpHeaderFields: [String: String]? = nil
    
    /// Read only property to get the current AVPlayer rate.
    open var rate: Float? {
        return player?.rate
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
    
    /// Read and set the current AVPlayer volume, a value of 0.0 indicates silence; a value of 1.0 indicates full audio volume for the player instance.
    open var volume: Float? {
        get {
            return player?.volume
        }
        set {
            guard let newValue = newValue, 0.0...1.0 ~= newValue else { return }
            player?.volume = newValue
        }
    }
    
    /// Player current state of type `State`
    open private(set) var state = State.urlNotSet {
        didSet {
            guard oldValue != state else { return }
            stateChange(with: state)
        }
    }
    
    /// Playing state of type `PlaybackState`
    open private(set) var playbackState = PlaybackState.stopped {
        didSet {
            guard oldValue != playbackState else { return }
            playbackStateChange(with: playbackState)
        }
    }
    
    // MARK: - Private properties
    
    /// Observations
    private var observations = [ObjectIdentifier : Observation]()
    
    /// AVPlayer
    private var player: AVPlayer?
    
    /// Last player item
    private var lastPlayerItem: AVPlayerItem?
    
    /// Check for headphones, used to handle audio route change
    private var headphonesConnected: Bool = false
    
    /// Default player item
    private var playerItem: AVPlayerItem? {
        didSet {
            playerItemDidChange()
        }
    }
    
    /// Reachability for network interruption handling
    private let reachability = Reachability()!
    
    /// Current network connectivity
    private var isConnected = false
    
    // MARK: - Initialization
    
    private override init() {
        super.init()

        #if !os(macOS)
        let options: AVAudioSession.CategoryOptions

        // Enable bluetooth playback
        #if os(iOS)
        options = [.defaultToSpeaker, .allowBluetooth, .allowAirPlay]
        #else
        options = []
        #endif

        // Start audio session
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode.default, options: options)
        #endif

        // Notifications
        setupNotifications()
        
        // Check for headphones
        #if os(iOS)
        checkHeadphonesConnection(outputs: AVAudioSession.sharedInstance().currentRoute.outputs)
        #endif

        // Reachability config
        try? reachability.startNotifier()
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        isConnected = reachability.connection != .none
    }
    
    // MARK: - Control Methods
    
    /**
     Trigger the play function of the radio player
     
     */
    open func play() {
        guard let player = player else { return }
        if player.currentItem == nil, playerItem != nil {
            player.replaceCurrentItem(with: playerItem)
        }
        
        player.play()
        playbackState = .playing
    }
    
    /**
     Trigger the pause function of the radio player
     
     */
    open func pause() {
        guard let player = player else { return }
        player.pause()
        playbackState = .paused
    }
    
    /**
     Trigger the stop function of the radio player
     
     */
    open func stop() {
        guard let player = player else { return }
        playbackState = .stopped
        player.replaceCurrentItem(with: nil)
        timedMetadataDidChange(rawValue: nil)
    }
    
    /**
     Toggle isPlaying state
     
     */
    open func togglePlaying() {
        isPlaying ? pause() : play()
    }
    
    // MARK: - Private helpers
    
    private func radioURLDidChange(with url: URL?) {
        resetPlayer()
        guard let url = url else { state = .urlNotSet; return }
        
        state = .loading
        
        var options: [String : Any]? = nil
        
        if let httpHeaderFields = httpHeaderFields {
            options = ["AVURLAssetHTTPHeaderFieldsKey": httpHeaderFields]
        }
        
        preparePlayer(with: AVURLAsset(url: url, options: options)) { (success, asset) in
            guard success, let asset = asset else {
                self.resetPlayer()
                self.state = .error
                return
            }
            self.setupPlayer(with: asset)
        }
    }
    
    private func setupPlayer(with asset: AVURLAsset) {

        if player == nil {
            player = AVPlayer()
            // Removes black screen when connecting to appleTV
            player?.allowsExternalPlayback = false
        }
        
        playerItem = AVPlayerItem(asset: asset)
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: DispatchQueue.main)
        playerItem?.add(metadataOutput)
    }
        
    /** Reset all player item observers and create new ones
     
     */
    private func playerItemDidChange() {
        
        guard lastPlayerItem != playerItem else { return }
        
        if let item = lastPlayerItem {
            pause()
            
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
            item.removeObserver(self, forKeyPath: "status")
            item.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        }
        
        lastPlayerItem = playerItem
        timedMetadataDidChange(rawValue: nil)
        
        if let item = playerItem {
            
            item.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
            item.addObserver(self, forKeyPath: "playbackBufferEmpty", options: NSKeyValueObservingOptions.new, context: nil)
            item.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: NSKeyValueObservingOptions.new, context: nil)
            
            player?.replaceCurrentItem(with: item)
            if isAutoPlay { play() }
        }
        
        itemChange(with: radioURL)
    }
    
    /** Prepare the player from the passed AVURLAsset
     
     */
    private func preparePlayer(with asset: AVURLAsset?, completionHandler: @escaping (_ isPlayable: Bool, _ asset: AVURLAsset?)->()) {
        guard let asset = asset else {
            completionHandler(false, nil)
            return
        }
        
        let requestedKey = ["playable"]
        
        asset.loadValuesAsynchronously(forKeys: requestedKey) {
            
            DispatchQueue.main.async {
                var error: NSError?
                
                let keyStatus = asset.statusOfValue(forKey: "playable", error: &error)
                if keyStatus == AVKeyValueStatus.failed || !asset.isPlayable {
                    completionHandler(false, nil)
                    return
                }
                
                completionHandler(true, asset)
            }
        }
    }
    
    private func timedMetadataDidChange(rawValue: String?) {
        let metadataCleaned = cleanMetadata(rawValue)
        let parts = metadataCleaned?.components(separatedBy: " - ")
        metadataChange(artistName: parts?.first, trackName: parts?.last)
        rawMetadataChange(rawValue: rawValue)
        shouldGetArtwork(for: rawValue, enableArtwork)
    }
    
    private func shouldGetArtwork(for rawValue: String?, _ enabled: Bool) {
        guard enabled else { return }
        guard let rawValue = rawValue else {
            artworkChange(url: nil)
            return
        }
        
        FRadioAPI.getArtwork(for: rawValue as String, size: artworkSize, completionHandler: { [weak self] artworlURL in
            DispatchQueue.main.async {
                self?.artworkChange(url: artworlURL)
            }
        })
    }
    
    private func cleanMetadata(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue else { return nil }
        return rawValue.replacingOccurrences(
            of: #"(\(.*?\)\w*)|(\[.*?\]\w*)"#,
            with: "",
            options: .regularExpression
        )
    }
    
    private func reloadItem() {
        player?.replaceCurrentItem(with: nil)
        player?.replaceCurrentItem(with: playerItem)
    }
    
    private func resetPlayer() {
        stop()
        playerItem = nil
        lastPlayerItem = nil
        player = nil
    }
    
    deinit {
        resetPlayer()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        #if os(iOS)
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        #endif
    }
    
    // MARK: - Responding to Interruptions
    
    @objc private func handleInterruption(notification: Notification) {
        #if os(iOS)
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
        @unknown default:
            break
        }
        #endif
    }
    
    @objc func reachabilityChanged(note: Notification) {
        
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
        
        player?.pause()
        
        // Wait 1 sec to recheck and make sure the reload is needed
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            if !item.isPlaybackLikelyToKeepUp { self.reloadItem() }
            self.isPlaying ? self.player?.play() : self.player?.pause()
        }
    }
    
    // MARK: - Responding to Route Changes
    #if os(iOS)
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
    #endif
    // MARK: - KVO
    
    /// :nodoc:
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if let item = object as? AVPlayerItem, let keyPath = keyPath, item == self.playerItem {
            
            switch keyPath {
                
            case "status":
                
                if player?.status == AVPlayer.Status.readyToPlay {
                    self.state = .readyToPlay
                } else if player?.status == AVPlayer.Status.failed {
                    self.state = .error
                }
                
            case "playbackBufferEmpty":
                
                if item.isPlaybackBufferEmpty {
                    self.state = .loading
                    self.checkNetworkInterruption()
                }
                
            case "playbackLikelyToKeepUp":
                
                self.state = item.isPlaybackLikelyToKeepUp ? .loadingFinished : .loading
                
            default:
                break
            }
        }
    }
}

extension FRadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    
    public func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        
        // make this an AVMetadata item
        guard let item = groups.first?.items.first else {
            timedMetadataDidChange(rawValue: nil)
            return
        }
        
        timedMetadataDidChange(rawValue: item.value as? String)
    }
}

private extension FRadioPlayer {
    
    private func stateChange(with state: FRadioPlayer.State) {
        notifiyObservers { observer in
            observer.radioPlayer(self, playerStateDidChange: state)
        }
    }
    
    private func playbackStateChange(with playbackState: FRadioPlayer.PlaybackState) {
        notifiyObservers { observer in
            observer.radioPlayer(self, playbackStateDidChange: playbackState)
        }
    }
    
    private func itemChange(with url: URL?) {
        notifiyObservers { observer in
            observer.radioPlayer(self, itemDidChange: url)
        }
    }
    
    private func metadataChange(artistName: String?, trackName: String?) {
        notifiyObservers { observer in
            observer.radioPlayer(self, metadataDidChange: artistName, trackName: trackName)
        }
    }
    
    private func rawMetadataChange(rawValue: String?) {
        notifiyObservers { observer in
            observer.radioPlayer(self, metadataDidChange: rawValue)
        }
    }
    
    private func artworkChange(url: URL?) {
        notifiyObservers { observer in
            observer.radioPlayer(self, artworkDidChange: url)
        }
    }
    
    private func notifiyObservers(with action: (_ observer: FRadioPlayerObserver) -> Void) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            
            action(observer)
        }
    }
}

private extension FRadioPlayer {
    struct Observation {
        weak var observer: FRadioPlayerObserver?
    }
}

public extension FRadioPlayer {
    func addObserver(_ observer: FRadioPlayerObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    func removeObserver(_ observer: FRadioPlayerObserver) {
        let id = ObjectIdentifier(observer)
        observations.removeValue(forKey: id)
    }
}
