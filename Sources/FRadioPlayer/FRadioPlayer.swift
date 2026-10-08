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
    
    /// Who recovers a stalled stream (default `.automatic`, the 0.4.0
    /// ladder). Switching to `.hostManaged` cancels any pending library
    /// reload. See `RecoveryPolicy`.
    public var recoveryPolicy: RecoveryPolicy = .automatic {
        didSet {
            if recoveryPolicy == .hostManaged { stallRecovery.cancel() }
        }
    }

    /// Called with every newly created `AVPlayerItem`, on the main actor,
    /// before the item is attached to the player: the place to install an
    /// `audioMix` (for example a processing tap). It is not called when
    /// `play()` reattaches a kept item. Do not retain the item; it is
    /// replaced on every `radioURL` change, on `play()` after an error and
    /// after `stop(discardingItem: true)`. A stop, discard or `radioURL`
    /// change made from inside the call wins: the item being configured is
    /// then dropped instead of attached. Default `nil`. Since 0.5.0.
    public var playerItemConfigurator: (@MainActor (AVPlayerItem) -> Void)?

    /// Increments every time the player creates a new item, so a host can
    /// tell a fresh item from a reattached one. Since 0.5.0.
    public private(set) var itemGeneration = 0

    /// Whether the player calls `play()` itself when an interruption ends
    /// with `shouldResume` and playback was running when it began (default
    /// `true`, the 0.4.0 behaviour). With `false` the player stays paused
    /// and `radioPlayer(_:interruptionEnded:)` tells the host whether a
    /// resume is warranted. Since 0.5.0.
    public var resumesAfterInterruption = true

    /// The failure behind the latest `.error` state, set just before
    /// observers get `radioPlayer(_:didFail:)`. Cleared when a new item is
    /// created (a radioURL change, or play() rebuilding after an error).
    public private(set) var lastFailure: Failure?

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

    /// Network connectivity as last reported by the path monitor
    struct Connectivity {
        /// Whether the latest path was satisfied
        var isConnected = false
        /// Whether any path was received yet. The monitor delivers the
        /// current path right after it starts: that first snapshot seeds
        /// connectivity, it is not a restoration.
        var hasSnapshot = false
    }

    /// Internal so tests can replay a cold start
    var connectivity = Connectivity()

    /// Current network connectivity
    private var isConnected: Bool { connectivity.isConnected }
    
    /// Key-value observing context
    private let requiredAssetKeys = [
        "playable",
        "hasProtectedContent"
    ]
    
    /// Player time observer
    private var timeObserver: Any?

    /// Progress-only time observer for live streams, where the file time
    /// observer is removed. Feeds `didObserveProgress` and nothing else.
    private(set) var liveProgressObserver: Any?

    /// Set by stop(discardingItem: true): the next play() builds a fresh
    /// item for the kept URL. Consumed by that play() before it builds, and
    /// cleared by any new item or URL change.
    private var needsFreshItem = false

    /// Identifies the item creation in flight; bumped by every new creation
    /// and by every stop, discard or URL change (see `setupPlayer`)
    private var itemCreation = 0

    /// The latest creation whose item was attached
    private var committedCreation = 0

    /// Whether the player is waiting for data while playback is wanted
    private(set) var isBuffering = false

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
            guard let self = self else { return }
            self.failPlayback(.stalledExhausted(attempts: self.stallRecovery.intervals.count))
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
        // of reattaching the dead item. So does the first play after
        // stop(discardingItem: true). The request is consumed before the
        // build starts, so a play() nested in a callback the build fires
        // (`.loading`, the configurator) cannot start a second build.
        if state == .error || needsFreshItem, let url = radioURL {
            needsFreshItem = false
            // A stop or URL change issued from the configurator wins
            guard rebuildPipeline(with: url) == .committed else { return }
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
        setBuffering(false)
        playbackState = .paused
    }
    
    /**
     Trigger the stop function of the radio player
     
     */
    open func stop() {
        stopPlayback(endingLoad: true)
    }

    /**
     Stops playback and optionally drops the current item.

     `stop(discardingItem: false)` is `stop()`: the item is kept and the
     next `play()` reattaches it. With `true` the item is also detached and
     released along with its metadata, artwork, duration and time, so the
     next `play()` for the same `radioURL` builds a fresh asset and item
     (`itemGeneration` increments and `playerItemConfigurator` runs). Use it
     for a live stop that must reconnect, not resume. Since 0.5.0.

     - parameter discardingItem: whether to drop the current item
     */
    public func stop(discardingItem: Bool) {
        stop()
        guard discardingItem else { return }
        discardItem()
    }

    private func discardItem() {
        invalidateItemCreation()
        removeFileTimeObserver()
        removeLiveProgressObserver()
        player?.replaceCurrentItem(with: nil)
        needsFreshItem = true
        // playerItemDidChange detaches the observers, forgets lastPlayerItem
        // and clears metadata and artwork
        playerItem = nil
        duration = 0
        currentTime = 0
    }

    private func removeFileTimeObserver() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    /// - parameter endingLoad: whether an in-flight load reports
    ///   `.loadingFinished`. A failure passes `false` and reports `.error`
    ///   instead, so observers never see a transient "finished" state.
    private func stopPlayback(endingLoad: Bool) {
        resumeAfterInterruption = nil
        invalidateItemCreation()
        guard let player = player else { return }
        stallRecovery.cancel()
        setBuffering(false)

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
        guard let url = url else {
            state = .urlNotSet
            itemChange(with: nil)
            return
        }

        // A URL switch from inside the configurator already reported the
        // item that replaced this one
        if rebuildPipeline(with: url) != .superseded {
            itemChange(with: url)
        }
    }

    /// Builds a fresh asset + item for the URL. Used on every radioURL change
    /// and on play() after a fatal error (failed items cannot be reused).
    @discardableResult
    private func rebuildPipeline(with url: URL) -> ItemCreation {
        state = .loading

        // No AVURLAssetPreferPreciseDurationAndTimingKey: `false` is already
        // the default, and passing it explicitly stopped a rebuilt item from
        // loading after an earlier failure on iOS (play-after-error)
        var options: [String: Any] = [:]

        if let httpHeaderFields = httpHeaderFields {
            options["AVURLAssetHTTPHeaderFieldsKey"] = httpHeaderFields
        }

        let asset = AVURLAsset(url: url, options: options)
        return setupPlayer(with: asset)
    }

    /// How an item creation ended once the configurator returned
    enum ItemCreation {
        /// The item was attached (and autoplayed if `isAutoPlay`)
        case committed
        /// A stop or discard during the configurator call: the item is
        /// dropped and the next play() builds a fresh one
        case stopped
        /// A radioURL change during the configurator call created a newer
        /// item, which stays
        case superseded
    }

    /// Any stop, discard or URL change invalidates a creation in flight
    private func invalidateItemCreation() {
        itemCreation += 1
    }

    private func setupPlayer(with asset: AVURLAsset) -> ItemCreation {

        if player == nil {
            player = AVPlayer()
            // Removes black screen when connecting to appleTV
            player?.allowsExternalPlayback = false
            observeTimeControlStatus()
        }
        
        lastFailure = nil
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: requiredAssetKeys)
        itemGeneration += 1
        needsFreshItem = false
        itemCreation += 1
        let creation = itemCreation
        playerItemConfigurator?(item)

        // The configurator may have stopped, discarded or switched URL:
        // attaching (and autoplaying) this item now would undo that
        guard creation == itemCreation else {
            if committedCreation > creation { return .superseded }
            if playerItem != nil { discardItem() }
            needsFreshItem = true
            return .stopped
        }
        committedCreation = creation
        playerItem = item
        return .committed
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
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: item)
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
            NotificationCenter.default.addObserver(self, selector: #selector(itemPlaybackStalled(_:)), name: .AVPlayerItemPlaybackStalled, object: item)

            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackBufferEmpty), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.duration), options: [.old, .new], context: FRadioPlayer.itemKVOContext)
            item.add(metadataOutput)
            
            player?.replaceCurrentItem(with: item)
            // A live item's duration starts indefinite and may never change,
            // so progress cannot wait for a duration notification. A finite
            // duration later swaps this for the file observer.
            installLiveProgressObserver()
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
        removeLiveProgressObserver()
        
        stop()
        stallRecovery.cancel()
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        didStartPlaying = false
        needsFreshItem = false
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
    /// Observers then get `interruptionEnded` with whether a resume is
    /// warranted, after the player acted on it (or, with
    /// `resumesAfterInterruption == false`, left it to the host).
    func interruptionEnded(shouldResume: Bool) {
        guard let resume = resumeAfterInterruption else {
            reportInterruptionEnded(shouldResume: false)
            return
        }
        resumeAfterInterruption = nil
        let warranted = shouldResume && resume
        if warranted {
            if resumesAfterInterruption { play() }
        } else {
            pause()
        }
        reportInterruptionEnded(shouldResume: warranted)
    }

    private func reportInterruptionEnded(shouldResume: Bool) {
        notifiyObservers { observer in
            observer.radioPlayer(self, interruptionEnded: shouldResume)
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
            setBuffering(false)
        case .waitingToPlayAtSpecifiedRate:
            // Waiting with playback intent is loading, whatever came before
            // (keeps state in sync when a stopped item is reattached by play)
            if playbackState == .playing, state != .error {
                state = .loading
            }
            if playbackState == .playing { setBuffering(true) }
            // Only recover mid-playback stalls: initial buffering manages
            // itself. A host-managed player never schedules a reload.
            guard recoveryPolicy == .automatic, didStartPlaying, playbackState == .playing else { return }
            stallRecovery.start()
        case .paused:
            setBuffering(false)
        @unknown default:
            break
        }
    }

    private func networkPathDidChange(_ path: NWPath) {
        connectivityDidChange(isConnected: path.status == .satisfied)
    }

    func connectivityDidChange(isConnected isNowConnected: Bool) {
        // Recover playback when the connection comes back after being lost
        if isNowConnected, !isConnected {
            // Only a path restored after a known unsatisfied one is a
            // reconnect; the monitor's first snapshot just seeds the state
            if connectivity.hasSnapshot, playerItem != nil, playbackState == .playing {
                reportStall(.networkReconnected)
            }
            // 0.4.0 behaviour kept as is: `isConnected` is still false here,
            // so this call never starts the ladder (see the 0.5.0 notes)
            checkNetworkInterruption()
        }

        connectivity.isConnected = isNowConnected
        connectivity.hasSnapshot = true
    }

    // Buffer-empty and network-reconnect signals route into the recovery
    // ladder. It is bounded, cancelable, and checks conditions at attempt
    // time, which removes the old captured-item race.
    private func checkNetworkInterruption() {
        guard
            recoveryPolicy == .automatic,
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

    /// The item the AVPlayer currently holds (nil when detached). Tests use
    /// it to tell a retained item from a reattached or fresh one.
    var attachedItem: AVPlayerItem? {
        player?.currentItem
    }

    func itemStatusDidChange(_ item: AVPlayerItem, newStatus: AVPlayerItem.Status?) {
        guard isItemAttached(item) else { return }
        let status = newStatus ?? .unknown

        switch status {
        case .readyToPlay:
            state = .readyToPlay
        case .failed:
            failPlayback(.classify(error: item.error, errorLog: item.errorLog()?.events.last.map(ErrorLogEntry.init)))
        default:
            break
        }
    }

    /// A fatal playback failure: stop cleanly (releases the connection,
    /// resets the playback state so play buttons don't lie) and report error.
    /// The failure is recorded and reported after playback stops and
    /// before `.error` is published.
    private func failPlayback(_ failure: Failure) {
        stopPlayback(endingLoad: false)
        lastFailure = failure
        notifiyObservers { observer in
            observer.radioPlayer(self, didFail: failure)
        }
        state = .error
    }

    func itemBufferEmptyDidChange(_ item: AVPlayerItem) {
        bufferEmptyDidChange(item, isEmpty: item.isPlaybackBufferEmpty)
    }

    func bufferEmptyDidChange(_ item: AVPlayerItem, isEmpty: Bool) {
        guard isItemAttached(item), isEmpty else { return }
        state = .loading
        if playbackState == .playing {
            setBuffering(true)
            reportStall(.bufferEmpty)
        }
        checkNetworkInterruption()
    }

    // MARK: - Host watchdog signals

    /// AVFoundation posts this on an unspecified thread: reduce it to the
    /// item's identity, then hop like the item KVO does
    @objc nonisolated func itemPlaybackStalled(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        let itemID = ObjectIdentifier(item)
        if Thread.isMainThread {
            MainActor.assumeIsolated { playbackStalled(itemID: itemID) }
        } else {
            Task { @MainActor [weak self] in self?.playbackStalled(itemID: itemID) }
        }
    }

    private func playbackStalled(itemID: ObjectIdentifier) {
        guard let item = playerItem, ObjectIdentifier(item) == itemID,
              playbackState == .playing else { return }
        reportStall(.playbackStalledNotification)
    }

    private func reportStall(_ reason: StallReason) {
        notifiyObservers { observer in
            observer.radioPlayerDidDetectStall(self, reason: reason)
        }
    }

    private func setBuffering(_ value: Bool) {
        guard isBuffering != value else { return }
        isBuffering = value
        notifiyObservers { observer in
            observer.radioPlayer(self, bufferingDidChange: value)
        }
    }

    func reportProgress(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return }
        notifiyObservers { observer in
            observer.radioPlayer(self, didObserveProgress: seconds)
        }
    }

    /// Progress only, for host watchdogs: legacy `currentTime` and
    /// `playTimeDidChange` are untouched. Bound to the current item
    /// generation, so a tick queued for an older item is dropped.
    private func installLiveProgressObserver() {
        removeLiveProgressObserver()
        let generation = itemGeneration
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        liveProgressObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] time in
            MainActor.assumeIsolated {
                self?.liveProgressTick(time, generation: generation)
            }
        })
    }

    private func liveProgressTick(_ time: CMTime, generation: Int) {
        guard playerItem != nil, itemGeneration == generation else { return }
        reportProgress(time)
    }

    private func removeLiveProgressObserver() {
        if let observer = liveProgressObserver {
            player?.removeTimeObserver(observer)
            liveProgressObserver = nil
        }
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
    
    /// - parameter generation: the item generation the observer was
    ///   installed for. A tick already queued when its observer was removed
    ///   still runs, and the legacy playTimeDidChange callback may discard
    ///   or replace the item: progress is only reported for the item the
    ///   sample was taken from, still current after the legacy callback.
    private func periodicTimeUpdate(_ time: CMTime, generation: Int) {
        guard !hasPlayedToEndTime else { return }
        let item = playerItem
        let playedTime = CMTimeGetSeconds(time)
        currentTime = playedTime
        guard let item = item, playerItem === item, itemGeneration == generation else { return }
        reportProgress(time)
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
    
    func durationDidChange(_ duration: CMTime) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        if CMTIME_IS_INDEFINITE(duration) || duration == .zero {
            // Live stream
            self.duration = 0
            
            if let timeObserver = self.timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }

            // Usually installed when the item was attached already
            if liveProgressObserver == nil {
                installLiveProgressObserver()
            }
            
        } else {
            // Audio file
            removeLiveProgressObserver()
            self.duration = Double(CMTimeGetSeconds(duration))
            
            // Registered on the main queue, so the block runs on the actor
            let generation = itemGeneration
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] time in
                MainActor.assumeIsolated {
                    self?.periodicTimeUpdate(time, generation: generation)
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
