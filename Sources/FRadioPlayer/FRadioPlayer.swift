//
//  FRadioPlayer.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2017-11-11.
//  Copyright © 2017 Fethi El Hassasna (@fethica). All rights reserved.
//

import AVFoundation
import Network

/**
 FRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.
 */

open class FRadioPlayer: NSObject {
    
    // MARK: - Properties
    
    /// Returns the singleton `FRadioPlayer` instance.
    public static let shared = FRadioPlayer()
    
    /// Enable / disable `playImmediately`. More info: https://developer.apple.com/documentation/avfoundation/avplayer/1643480-playimmediately
    open var isPlayImmediately: Bool = false
    
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
    
    /// Artwork API of type `FRadioArtworkAPI`. Default: iTunesAPI(artworkSize: 300)
    open var artworkAPI: FRadioArtworkAPI = iTunesAPI(artworkSize: 300)
    
    /// HTTP headers for AVURLAsset (Ex: `["user-agent": "FRadioPlayer"]`).
    open var httpHeaderFields: [String: String]? = nil
    
    /// Metadata extractor of type `FRadioMetadataExtractor`
    open var metadataExtractor: FRadioMetadataExtractor = DefaultMetadataExtractor()
    
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
    
    /// Current metadata value of type `FRadioPlayer.Metadata`
    open private(set) var currentMetadata: Metadata? = nil {
        didSet {
            metadataChange(currentMetadata)
            shouldGetArtwork(for: currentMetadata, enableArtwork)
        }
    }
    
    /// Current artwork URL value of type `URL`
    open private(set) var currentArtworkURL: URL? = nil {
        didSet {
            guard oldValue != currentArtworkURL else { return }
            artworkChange(url: currentArtworkURL)
        }
    }
    
    /// Store the item duration, == 0 if not available
    open private(set) var duration: TimeInterval = 0 {
        didSet {
            guard oldValue != duration else { return }
            notifiyObservers { observer in
                observer.radioPlayer(self, durationDidChange: duration)
            }
        }
    }
    
    /// Store the current time, == 0 if not available
    open private(set) var currentTime: Double = 0 {
        didSet {
            guard oldValue != currentTime else { return }
            notifiyObservers { observer in
                observer.radioPlayer(self, playTimeDidChange: currentTime, duration: duration)
            }
        }
    }
    
    // MARK: - Internal / Private properties
    
    /// Observations
    var observations = [ObjectIdentifier : Observation]()
    
    /// Metadata Output
    var metadataOutput: AVPlayerItemMetadataOutput
    
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
    
    /// Network path monitor for interruption handling
    private let pathMonitor = NWPathMonitor()

    /// Current network connectivity
    private var isConnected = false
    
    /// Key-value observing context
    private var playerItemContext = 0
    
    /// Key-value observing context
    private let requiredAssetKeys = [
        "playable",
        "hasProtectedContent"
    ]
    
    /// Player time observer
    private var timeObserver: Any?

    /// Item played to the end
    private var hasPlayedToEndTime = false

    /// Recovery ladder for mid-playback stalls (bounded, cancelable)
    private let stallRecovery = StallRecovery()

    /// Modern playback progress signal, observed on the player
    private var timeControlObservation: NSKeyValueObservation?

    /// Whether the current item ever reached actual playback. Gates stall
    /// recovery so slow initial loads are not punished with reloads.
    private var didStartPlaying = false
    
    // MARK: - Initialization
    
    private override init() {
        metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        
        super.init()

        #if !os(macOS)
        let options: AVAudioSession.CategoryOptions

        // Enable AirPlay and Bluetooth A2DP for playback
        #if os(iOS)
        options = [.allowAirPlay, .allowBluetoothA2DP]
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

        // Network path monitoring config. The handler fires once right after
        // start with the current path, which seeds `isConnected`; the
        // reload check it may trigger is inert at init (playerItem is nil).
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.networkPathDidChange(path)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "FRadioPlayer.pathMonitor"))
        
        // Setup Metadata Output Delegate
        metadataOutput.setDelegate(self, queue: DispatchQueue.main)

        // Stall recovery wiring: attempts reload while the stall persists,
        // gives up into a stopped + error state when the ladder exhausts
        stallRecovery.onAttempt = { [weak self] in
            guard let self = self, let item = self.playerItem else { return true }
            if item.isPlaybackLikelyToKeepUp { return true } // recovered on its own
            guard self.isConnected else { return false }     // offline: keep climbing
            self.reloadItem()
            return false // success surfaces as .playing, which cancels the ladder
        }
        stallRecovery.onExhausted = { [weak self] in
            self?.failPlayback()
        }
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
        
        isPlayImmediately ? player.playImmediately(atRate: 1.0) : player.play()
        playbackState = .playing
    }
    
    /**
     Trigger the pause function of the radio player
     */
    open func pause() {
        guard let player = player else { return }
        stallRecovery.cancel()
        player.pause()
        playbackState = .paused
    }
    
    /**
     Trigger the stop function of the radio player
     
     */
    open func stop() {
        guard let player = player else { return }
        stallRecovery.cancel()

        if duration != 0 {
            currentTime = 0
            player.pause()
            player.seek(to: .zero)
        } else {
            // Drop the rate first: replacing the item alone leaves the player
            // armed (rate 1, waiting), which is why stopping during loading
            // used to not stick (issue #12)
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentMetadata = nil
            currentArtworkURL = nil
        }

        // Stopping an in-flight load detaches the item, so the loading
        // lifecycle is over: without this, `state` freezes on .loading
        // (a proper .stopped/.idle case in State is a v1.0 vocabulary change)
        if state == .loading {
            state = .loadingFinished
        }

        playbackState = .stopped
    }
    
    /**
     Triggers the seek to a given time
     
     - parameter seconds: time in seconds to seek to
     - parameter completion: optional completion
     */
    open func seek(to seconds: TimeInterval, completion: (() -> Void)?) {
        guard duration != 0 else { return }
        
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 1)
        
        player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .positiveInfinity, completionHandler: { [weak self] _ in
            self?.play()
            completion?()
        })
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

        // Exactly one itemDidChange per radioURL change, after all setup work
        defer { itemChange(with: url) }

        guard let url = url else { state = .urlNotSet; return }
        
        state = .loading
        
        var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        
        if let httpHeaderFields = httpHeaderFields {
            options["AVURLAssetHTTPHeaderFieldsKey"] = httpHeaderFields
        }
        
        let asset = AVURLAsset(url: url, options: options)
        setupPlayer(with: asset)
    }
    
    private func setupPlayer(with asset: AVURLAsset) {

        if player == nil {
            player = AVPlayer()
            // Removes black screen when connecting to appleTV
            player?.allowsExternalPlayback = false
            observeTimeControlStatus()
        }
        
        playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: requiredAssetKeys)
    }
        
    /** Reset all player item observers and create new ones
     
     */
    private func playerItemDidChange() {
        
        guard lastPlayerItem != playerItem else { return }
        
        if let item = lastPlayerItem {
            // Only pause if something was actually playing: tearing down an
            // idle item must not emit a spurious playback state change
            if isPlaying { pause() }

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty))
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp))
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.duration))
            item.remove(metadataOutput)
        }
        
        lastPlayerItem = playerItem
        didStartPlaying = false
        currentMetadata = nil
        currentArtworkURL = nil
        
        if let item = playerItem {
            NotificationCenter.default.addObserver(self, selector: #selector(itemDidPlayToEnd), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: &playerItemContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty), options: [.old, .new], context: &playerItemContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp), options: [.old, .new], context: &playerItemContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.duration), options: [.old, .new], context: &playerItemContext)
            item.add(metadataOutput)
            
            player?.replaceCurrentItem(with: item)
            if isAutoPlay { play() }
        }
    }
    
    private func shouldGetArtwork(for metadata: FRadioPlayer.Metadata?, _ enabled: Bool) {
        guard enabled else { return }
        guard let metadata = metadata else {
            currentArtworkURL = nil
            return
        }
        
        artworkAPI.getArtwork(for: metadata) { [weak self] artworlURL in
            DispatchQueue.main.async {
                self?.currentArtworkURL = artworlURL
            }
        }
    }
    
    private func reloadItem() {
        player?.replaceCurrentItem(with: nil)
        player?.replaceCurrentItem(with: playerItem)
    }
    
    private func resetPlayer() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        stop()
        stallRecovery.cancel()
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        didStartPlaying = false
        playerItem = nil
        lastPlayerItem = nil
        player = nil
        duration = 0
        currentTime = 0
    }
    
    deinit {
        resetPlayer()
        pathMonitor.cancel()
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
    
    // MARK: - Stall detection (timeControlStatus)

    private func observeTimeControlStatus() {
        timeControlObservation?.invalidate()
        timeControlObservation = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.timeControlStatusDidChange() }
        }
    }

    private func timeControlStatusDidChange() {
        guard let player = player else { return }

        switch player.timeControlStatus {
        case .playing:
            didStartPlaying = true
            stallRecovery.cancel()
        case .waitingToPlayAtSpecifiedRate:
            // Only recover mid-playback stalls: initial buffering manages itself
            guard didStartPlaying, playbackState == .playing else { return }
            stallRecovery.start()
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func networkPathDidChange(_ path: NWPath) {
        let isNowConnected = path.status == .satisfied

        // Recover playback when the connection comes back after being lost
        if isNowConnected, !isConnected {
            checkNetworkInterruption()
        }

        isConnected = isNowConnected
    }

    // Buffer-empty and network-reconnect signals route into the recovery
    // ladder. It is bounded, cancelable, and checks conditions at attempt
    // time, which removes the old captured-item race.
    private func checkNetworkInterruption() {
        guard
            let item = playerItem,
            !item.isPlaybackLikelyToKeepUp,
            isConnected,
            didStartPlaying, playbackState == .playing else { return }

        stallRecovery.start()
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
        
        // Only handle observations for the playerItemContext
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if let item = object as? AVPlayerItem, let keyPath = keyPath, item == self.playerItem {

            switch keyPath {
            case #keyPath(AVPlayerItem.status):
                itemStatusDidChange(item, change: change)
            case #keyPath(AVPlayerItem.isPlaybackBufferEmpty):
                itemBufferEmptyDidChange(item)
            case #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp):
                itemKeepUpDidChange(item)
            case #keyPath(AVPlayerItem.duration):
                itemDurationDidChange(item)
            default:
                break
            }
        }
    }

    // MARK: - Item KVO handlers

    /// Item KVO only drives the loading vocabulary while the item is attached
    /// to the player: after stop() detaches an item, its asynchronous buffer
    /// churn must not resurrect the .loading state.
    private func isItemAttached(_ item: AVPlayerItem) -> Bool {
        player?.currentItem === item
    }

    func itemStatusDidChange(_ item: AVPlayerItem, change: [NSKeyValueChangeKey: Any]?) {
        guard isItemAttached(item) else { return }

        let status: AVPlayerItem.Status
        if let statusNumber = change?[.newKey] as? NSNumber, let statusValue = AVPlayerItem.Status(rawValue: statusNumber.intValue) {
            status = statusValue
        } else {
            status = .unknown
        }

        switch status {
        case .readyToPlay:
            state = .readyToPlay
        case .failed:
            failPlayback()
        default:
            break
        }
    }

    /// A fatal playback failure: stop cleanly (releases the connection,
    /// resets the playback state so play buttons don't lie) and report error.
    private func failPlayback() {
        stop()
        state = .error
    }

    func itemBufferEmptyDidChange(_ item: AVPlayerItem) {
        guard isItemAttached(item), item.isPlaybackBufferEmpty else { return }
        state = .loading
        checkNetworkInterruption()
    }

    func itemKeepUpDidChange(_ item: AVPlayerItem) {
        guard isItemAttached(item) else { return }
        state = item.isPlaybackLikelyToKeepUp ? .loadingFinished : .loading
    }

    func itemDurationDidChange(_ item: AVPlayerItem) {
        guard isItemAttached(item) else { return }
        durationDidChange(item.duration)
    }
}

extension FRadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    
    public func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        
        currentMetadata = metadataExtractor.extract(from: groups)
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
    
    private func metadataChange(_ metaData: Metadata?) {
        notifiyObservers { observer in
            observer.radioPlayer(self, metadataDidChange: metaData)
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

// MARK: - Audio file support

private extension FRadioPlayer {
    
    private func periodicTimeUpdate(_ time: CMTime) {
        guard !hasPlayedToEndTime else { return }
        let playedTime = CMTimeGetSeconds(time)
        currentTime = playedTime
    }
    
    @objc private func itemDidPlayToEnd() {
        pause()
        hasPlayedToEndTime = true
        
        player?.seek(to: .zero) { [weak self] _ in
            self?.hasPlayedToEndTime = false
        }
    }
    
    private func durationDidChange(_ duration: CMTime) {
        
        if CMTIME_IS_INDEFINITE(duration) || duration == .zero {
            // Live stream
            self.duration = 0
            
            if let timeObserver = self.timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            
        } else {
            // Audio file
            self.duration = Double(CMTimeGetSeconds(duration))
            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] time in
                self?.periodicTimeUpdate(time)
            })
        }
    }
}
