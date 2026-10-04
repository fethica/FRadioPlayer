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

 The player is bound to the main actor: call it from the main actor, and every
 observer callback is delivered there. AVFoundation and audio session callbacks
 that can arrive on other threads are received `nonisolated` and hopped onto the
 main actor before they touch player state.
 */
@MainActor
open class FRadioPlayer: NSObject {
    
    // MARK: - Properties
    
    /// Returns the singleton `FRadioPlayer` instance.
    public static let shared = FRadioPlayer()

    /// Whether the player sets the shared `AVAudioSession` category to
    /// `.playback` when `shared` is first accessed (default `true`).
    ///
    /// An app that configures its own audio session sets this to `false`
    /// before its first access to `FRadioPlayer.shared`. Changing it later
    /// has no effect. Ignored on macOS, which has no `AVAudioSession`.
    public static var configuresAudioSession = true
    
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
    
    /// Default player item
    private(set) var playerItem: AVPlayerItem? {
        didSet {
            playerItemDidChange()
        }
    }
    
    /// Network path monitor for interruption handling
    private let pathMonitor = NWPathMonitor()

    /// Current network connectivity
    private var isConnected = false
    
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
    let stallRecovery = StallRecovery()

    /// Whether playback resumes when the current interruption ends with
    /// `shouldResume`. Nil outside an interruption, and cleared by any
    /// explicit play, pause or stop, so a user decision always wins.
    private var resumeAfterInterruption: Bool?

    /// Identifies the latest artwork lookup. A lookup that completes after
    /// newer metadata (or none) has arrived is dropped.
    private var artworkRequest = 0

    /// Modern playback progress signal, observed on the player
    private var timeControlObservation: NSKeyValueObservation?

    /// Whether the current item ever reached actual playback. Gates stall
    /// recovery so slow initial loads are not punished with reloads.
    private var didStartPlaying = false
    
    // MARK: - Initialization
    
    private override init() {
        metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        
        super.init()

        Self.configureAudioSessionIfNeeded { try? Self.applyPlaybackCategory() }

        // Notifications
        setupNotifications()
        
        // Network path monitoring config. The handler fires once right after
        // start with the current path, which seeds `isConnected`; the
        // reload check it may trigger is inert at init (playerItem is nil).
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
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
            // Defense in depth: every path that leaves .playing cancels the
            // ladder, but an attempt must never reload against user intent
            guard self.playbackState == .playing else { return true }
            if item.isPlaybackLikelyToKeepUp { return true } // recovered on its own
            guard self.isConnected else { return false }     // offline: keep climbing
            self.reloadItem()
            return false // success surfaces as .playing, which cancels the ladder
        }
        stallRecovery.onExhausted = { [weak self] in
            self?.failPlayback()
        }
    }
    
    // MARK: - Audio session

    /// Runs `apply` unless the app opted out with `configuresAudioSession`.
    static func configureAudioSessionIfNeeded(_ apply: () -> Void) {
        guard configuresAudioSession else { return }
        apply()
    }

    static func applyPlaybackCategory() throws {
        #if !os(macOS)
        // Playback supports AirPlay and A2DP by default. Explicit allowAirPlay is
        // only valid for playAndRecord and makes physical devices reject this category.
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        #endif
    }

    // MARK: - Control Methods
    
    /**
     Trigger the play function of the radio player
     
     */
    open func play() {
        resumeAfterInterruption = nil

        // A failed pipeline is terminal (failed AVPlayerItems can never play
        // again): pressing play after an error rebuilds from the URL instead
        // of reattaching the dead item
        if state == .error, let url = radioURL {
            rebuildPipeline(with: url)
        }

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
        resumeAfterInterruption = nil
        guard let player = player else { return }
        stallRecovery.cancel()
        player.pause()
        playbackState = .paused
    }
    
    /**
     Trigger the stop function of the radio player
     
     */
    open func stop() {
        stopPlayback(endingLoad: true)
    }

    /// - parameter endingLoad: whether an in-flight load reports
    ///   `.loadingFinished`. A failure passes `false` and reports `.error`
    ///   instead, so observers never see a transient "finished" state.
    private func stopPlayback(endingLoad: Bool) {
        resumeAfterInterruption = nil
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
        if endingLoad, state == .loading {
            state = .loadingFinished
        }

        playbackState = .stopped
    }
    
    /**
     Seeks the current item to a given time.

     The completion is called exactly once, on the main actor, after this
     method returns. That holds on every path: a live stream or an item whose
     duration is not known yet (no seek happens), no loaded item, a seek that
     AVFoundation reports as unfinished, and a seek superseded by a newer one.

     Seeking keeps the playback intent: a player that is playing keeps
     playing, and a paused or stopped player stays that way. A pause or stop
     issued while the seek is in flight wins.

     - parameter seconds: time in seconds to seek to
     - parameter completion: optional completion, called once on the main actor
     */
    open func seek(to seconds: TimeInterval, completion: (() -> Void)?) {
        // Bind the caller's completion to the main actor here; AVPlayer calls
        // its own handler on an unspecified queue
        let completion: (@MainActor () -> Void)? = completion.map { done in
            return { @MainActor in done() }
        }

        guard let player = player, duration != 0 else {
            if let completion = completion {
                Task { @MainActor in completion() }
            }
            return
        }

        let wasPlaying = playbackState == .playing
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)

        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .positiveInfinity, completionHandler: { [weak self] finished in
            Task { @MainActor in
                self?.seekDidComplete(finished: finished, wasPlaying: wasPlaying)
                completion?()
            }
        })
    }

    /// Resumes only a player that was playing when the seek was issued and
    /// still is. An unfinished seek leaves playback to whatever superseded it.
    private func seekDidComplete(finished: Bool, wasPlaying: Bool) {
        guard finished, wasPlaying, playbackState == .playing else { return }
        play()
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

        rebuildPipeline(with: url)
    }

    /// Builds a fresh asset + item for the URL. Used on every radioURL change
    /// and on play() after a fatal error (failed items cannot be reused).
    private func rebuildPipeline(with url: URL) {
        state = .loading

        // No AVURLAssetPreferPreciseDurationAndTimingKey: `false` is already
        // the default, and passing it explicitly stopped a rebuilt item from
        // loading after an earlier failure on iOS (play-after-error)
        var options: [String: Any] = [:]

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

            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.duration), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.add(metadataOutput)
            
            player?.replaceCurrentItem(with: item)
            if isAutoPlay { play() }
        }
    }
    
    private func shouldGetArtwork(for metadata: FRadioPlayer.Metadata?, _ enabled: Bool) {
        // Any newer metadata, including none after a station change or a
        // stop, supersedes a lookup still in flight
        artworkRequest += 1
        let request = artworkRequest

        guard enabled else { return }
        guard let metadata = metadata else {
            currentArtworkURL = nil
            return
        }
        
        // Providers may complete on any queue. The protocol has no cancel
        // hook, so a superseded lookup still runs; its result is dropped.
        artworkAPI.getArtwork(for: metadata) { [weak self] artworkURL in
            Task { @MainActor in
                guard let self = self, self.artworkRequest == request else { return }
                self.currentArtworkURL = artworkURL
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
        // Runs off the actor, so only nonisolated teardown belongs here.
        // The shared instance never deinitializes; a player that did would
        // still hold its item observers until the item is released.
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
    
    /// AVAudioSession posts this on the main thread, but a selector carries
    /// no isolation: receive it nonisolated and hop explicitly
    @objc nonisolated private func handleInterruption(notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }
        switch type {
        case .began:
            Task { @MainActor in self.interruptionBegan() }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { break }
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            Task { @MainActor in self.interruptionEnded(shouldResume: shouldResume) }
        @unknown default:
            break
        }
        #endif
    }

    /// Pauses and remembers whether playback was running. A repeated
    /// `.began` keeps the intent recorded by the first one.
    func interruptionBegan() {
        let resume = resumeAfterInterruption ?? (playbackState == .playing)
        pause()
        resumeAfterInterruption = resume
    }

    /// Resumes only when the system allows it and the player was playing
    /// when the interruption began. Does nothing when no interruption is
    /// pending or the user already played, paused or stopped during it.
    func interruptionEnded(shouldResume: Bool) {
        guard let resume = resumeAfterInterruption else { return }
        resumeAfterInterruption = nil
        if shouldResume, resume {
            play()
        } else {
            pause()
        }
    }
    
    // MARK: - Stall detection (timeControlStatus)

    private func observeTimeControlStatus() {
        timeControlObservation?.invalidate()
        timeControlObservation = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.timeControlStatusDidChange() }
        }
    }

    private func timeControlStatusDidChange() {
        guard let player = player else { return }
        handleTimeControlStatus(player.timeControlStatus)
    }

    func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            didStartPlaying = true
            stallRecovery.cancel()
            // Audio is flowing: a lingering .loading would be out of sync
            if state == .loading { state = .loadingFinished }
        case .waitingToPlayAtSpecifiedRate:
            // Waiting with playback intent is loading, whatever came before
            // (keeps state in sync when a stopped item is reattached by play)
            if playbackState == .playing, state != .error {
                state = .loading
            }
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
    /// AVAudioSession posts route changes on a secondary thread
    @objc nonisolated private func handleRouteChange(notification: Notification) {

        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else { return }
        
        switch reason {
        case .oldDeviceUnavailable:
            // 0.3.0 behavior, unchanged: losing a route pauses. The
            // headphones check that appeared to gate this never held (its
            // flag was always false), so it is gone; a route-aware pause
            // policy is 0.4.x work
            Task { @MainActor in self.pause() }
        default: break
        }
    }
    #endif
    // MARK: - KVO
    
    /// Context for the player item observations: the address of an object
    /// that lives for the whole process, so nonisolated code can compare it
    /// without touching actor state
    nonisolated static var itemKVOContext: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(itemKVOContextToken).toOpaque()
    }

    /// :nodoc:
    /// AVPlayerItem serializes its KVO on the main queue by default
    /// (AVPlayerItem.h), but a detached item has no player to serialize on.
    /// The change is reduced to Sendable values before it crosses to the
    /// main actor: synchronously when it arrives on the main thread, through
    /// an explicit hop otherwise.
    nonisolated override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == FRadioPlayer.itemKVOContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        guard let keyPath = keyPath, let item = object as? AVPlayerItem else { return }

        receiveItemKVO(PlayerItemKVOEvent(
            keyPath: keyPath,
            itemID: ObjectIdentifier(item),
            newStatus: (change?[.newKey] as? NSNumber)?.intValue
        ))
    }

    nonisolated func receiveItemKVO(_ event: PlayerItemKVOEvent) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { handleItemKVO(event) }
        } else {
            Task { @MainActor [weak self] in self?.handleItemKVO(event) }
        }
    }

    private func handleItemKVO(_ event: PlayerItemKVOEvent) {
        // Only the current item drives state; a replaced item's late
        // notifications are dropped
        guard let item = playerItem, ObjectIdentifier(item) == event.itemID else { return }

        switch event.keyPath {
        case #keyPath(AVPlayerItem.status):
            itemStatusDidChange(item, newStatus: event.newStatus.flatMap(AVPlayerItem.Status.init(rawValue:)))
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

    // MARK: - Item KVO handlers

    /// Item KVO only drives the loading vocabulary while the item is attached
    /// to the player: after stop() detaches an item, its asynchronous buffer
    /// churn must not resurrect the .loading state.
    private func isItemAttached(_ item: AVPlayerItem) -> Bool {
        player?.currentItem === item
    }

    func itemStatusDidChange(_ item: AVPlayerItem, newStatus: AVPlayerItem.Status?) {
        guard isItemAttached(item) else { return }
        let status = newStatus ?? .unknown

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
        stopPlayback(endingLoad: false)
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

// The player hands AVFoundation the main queue in `setDelegate(_:queue:)`,
// so delivery is on the main actor by construction. The payload
// (`AVTimedMetadataGroup`) is not Sendable and cannot be hopped, so the
// method stays isolated and the `@preconcurrency` conformance has the
// compiler check the delivery queue at runtime.
extension FRadioPlayer: @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    
    /// :nodoc:
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

extension FRadioPlayer {
    
    private func periodicTimeUpdate(_ time: CMTime) {
        guard !hasPlayedToEndTime else { return }
        let playedTime = CMTimeGetSeconds(time)
        currentTime = playedTime
    }
    
    /// AVPlayerItemDidPlayToEndTime may post on a thread other than the
    /// one that registered for it
    @objc nonisolated func itemDidPlayToEnd() {
        Task { @MainActor in self.playbackDidReachEnd() }
    }

    private func playbackDidReachEnd() {
        pause()
        hasPlayedToEndTime = true

        player?.seek(to: .zero) { [weak self] _ in
            Task { @MainActor in self?.hasPlayedToEndTime = false }
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
            
            // Registered on the main queue, so the block runs on the actor
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] time in
                MainActor.assumeIsolated {
                    self?.periodicTimeUpdate(time)
                }
            })
        }
    }
}

/// An item KVO notification reduced to Sendable values, so it can cross
/// from AVFoundation's thread to the main actor
struct PlayerItemKVOEvent: Sendable {
    let keyPath: String
    let itemID: ObjectIdentifier
    let newStatus: Int?
}

/// Its address is the KVO context for player item observations
private final class ItemKVOContextToken: Sendable {}
private let itemKVOContextToken = ItemKVOContextToken()
