<p align="center">
  <img src="Assets/logo.png" width="128" alt="FRadioPlayer logo: a white transport bar under an artwork card on a coral-to-red tile">
</p>

<h1 align="center">FRadioPlayer</h1>

<p align="center">
  <a href="https://github.com/fethica/FRadioPlayer/actions/workflows/spm.yml"><img src="https://github.com/fethica/FRadioPlayer/actions/workflows/spm.yml/badge.svg" alt="SPM"></a>
  <a href="https://github.com/fethica/FRadioPlayer/actions/workflows/demo.yml"><img src="https://github.com/fethica/FRadioPlayer/actions/workflows/demo.yml/badge.svg" alt="Demo"></a>
  <a href="https://github.com/fethica/FRadioPlayer/releases/latest"><img src="https://img.shields.io/github/v/release/fethica/FRadioPlayer" alt="Latest release"></a>
  <a href="https://swiftpackageindex.com/fethica/FRadioPlayer"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffethica%2FFRadioPlayer%2Fbadge%3Ftype%3Dplatforms" alt="Platforms"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
</p>

FRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.

## Example

SwiftUI demo source lives under `Example/FRadioPlayerDemo/`.

Use XcodeGen to generate and open the demo project:

```sh
brew install xcodegen    # once
cd Example
xcodegen                 # generates FRadioPlayerDemo.xcodeproj
open FRadioPlayerDemo.xcodeproj
```

## Features
- [x] Support internet radio URL playback
- [x] Update and parse track metadata
- [x] Update and show album artwork (via iTunes API)
- [x] Automatic handling of interruptions
- [x] Automatic handling of route changes
- [x] Support bluetooth playback
- [x] Network interruptions handling
- [x] Automatic stall recovery with bounded retries (reload with backoff, clean error state when the stream is gone)
- [x] Host-managed recovery, classified failures and item seams for apps that own playback (0.5.0)
- [x] Support for Swift Package Manager SPM

## Requirements
- iOS 14.0+
- macOS 11.0+
- tvOS 14.0+
- Xcode 16+ (Swift 6 toolchain; the package builds in Swift 6 language mode, your app can stay in Swift 5 mode)

## Installation

### Swift Package Manager

FRadioPlayer is available through [SPM](https://github.com/apple/swift-package-manager). To add it in Xcode: File > Add Packages… and use the URL of this repository. Or add the dependency in `Package.swift`:

```swift
.package(url: "https://github.com/fethica/FRadioPlayer.git", from: "0.4.0")
```

## Quick Start

Add the package, then use the shared player and observe changes.

```swift
import FRadioPlayer

// Adopting FRadioPlayerObserver here makes the class main-actor isolated
final class RadioController: NSObject, FRadioPlayerObserver {
    let player = FRadioPlayer.shared

    override init() {
        super.init()
        player.addObserver(self)
        player.enableArtwork = true      // Optional (default true)
        player.isAutoPlay = true         // Optional (default true)
        player.radioURL = URL(string: "https://your.station/stream.mp3")
        // Or manually control playback: player.play()
    }

    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
        print("Player state: \(state)")
    }
}

// From a nonisolated context, hop to the main actor
Task { @MainActor in
    FRadioPlayer.shared.togglePlaying()   // Play/Pause
    FRadioPlayer.shared.stop()            // Stop
    FRadioPlayer.shared.volume = 0.8      // Set volume (0.0...1.0)
}
```

### Manual

Prefer SPM. If needed, drag `Sources/FRadioPlayer` into your Xcode project.

## Concurrency

Since 0.4.0 `FRadioPlayer` is bound to the main actor and the package builds in Swift 6 language mode.

- Call the player from the main actor. From a background context, hop first: `Task { @MainActor in FRadioPlayer.shared.play() }`.
- Observer callbacks arrive on the main actor. A class that adopts `FRadioPlayerObserver` in its declaration is inferred `@MainActor`. A conformance added in an extension keeps the type's own isolation and still compiles.
- A controller that calls the player from its own methods must be main-actor isolated. Add `@MainActor` to the class, as the demo's `RadioPlayer` does. This applies in Swift 5 mode too: calling an isolated method from a nonisolated one is an error, not a warning.
- `FRadioPlayer.State` and `FRadioPlayer.PlaybackState` are `Sendable`. `FRadioPlayer.Metadata` is not, because it carries `AVTimedMetadataGroup` values; keep it on the main actor.
- Custom `FRadioArtworkAPI` providers receive a `@Sendable` completion and may call it from any queue. Existing providers written with a plain completion keep compiling.
- AVFoundation and audio session callbacks that can arrive off the main thread are received `nonisolated` inside the library and hopped explicitly. Nothing is marked `@unchecked Sendable` or `nonisolated(unsafe)`.

See the [0.4.0 release notes and migration guide](.github/release-notes/0.4.0.md) when upgrading from 0.3.x.

## Audio session

On iOS and tvOS the player sets the shared `AVAudioSession` category to `.playback`, with the default mode and no category options, when `FRadioPlayer.shared` is first accessed. The playback category supports AirPlay and Bluetooth A2DP without additional options on iOS.

An app that owns its audio session opts out on the main actor before its first access to `shared`, for example in its `App` initializer or `application(_:didFinishLaunchingWithOptions:)`:

```swift
FRadioPlayer.configuresAudioSession = false
```

Setting it after `shared` exists has no effect. The player never activates or deactivates the session.

## Host-managed recovery and seams

Since 0.5.0 an app that wants to own retries, interruptions or the audio pipeline can take them over. Every seam is opt-in: with the defaults the player behaves exactly as in 0.4.0.

| Seam | Default | What it lets the host do |
| --- | --- | --- |
| `recoveryPolicy` | `.automatic` | `.hostManaged` stops the built-in 2/4/8 s reload ladder. The player only reports stalls. |
| `radioPlayerDidDetectStall(_:reason:)` | no-op | Hear about `.bufferEmpty`, `.networkReconnected` and `.playbackStalledNotification` while playback is wanted, under either policy. |
| `radioPlayer(_:bufferingDidChange:)` | no-op | Track waiting-for-data periods (deduplicated). Starts on `timeControlStatus` waiting or buffer-empty with playback wanted; ends on `timeControlStatus` playing or paused, pause, stop and failure. `isPlaybackLikelyToKeepUp` is not a source (it only drives the legacy `state`). |
| `radioPlayer(_:didObserveProgress:)` | no-op | A tick every 0.5 s while time advances, for files and live streams (from attachment, even if the duration stays indefinite), for watchdogs. AVPlayer also ticks on start, stop and time jumps: compare successive times. |
| `lastFailure`, `radioPlayer(_:didFail:)` | no-op | A classified `Failure` (`.notFound`, `.forbidden`, `.unauthorized`, `.network`, `.timeout`, `.decode`, `.stalledExhausted`, `.unknown`, plus domain, code and HTTP status) delivered before the `.error` state. |
| `stop(discardingItem:)` | `stop()` keeps the item | `true` drops the item, metadata and artwork, so the next `play()` reconnects with a fresh item. |
| `playerItemConfigurator` | `nil` | Configure every new `AVPlayerItem` before it is attached, for example to install an `audioMix`. |
| `itemGeneration` | starts at 0 | Increments on every new item, to tell a fresh item from a reattached one. |
| `resumesAfterInterruption`, `radioPlayer(_:interruptionEnded:)` | `true`, no-op | `false` keeps the player paused when an interruption ends; the callback says whether resuming is warranted. |

A host that owns its retry ladder:

```swift
@MainActor
final class PlaybackAuthority: FRadioPlayerObserver {
    let player = FRadioPlayer.shared

    init() {
        player.recoveryPolicy = .hostManaged
        player.resumesAfterInterruption = false
        player.playerItemConfigurator = { item in
            item.audioMix = makeLoudnessMix(for: item)   // your tap
        }
        player.addObserver(self)
    }

    func radioPlayerDidDetectStall(_ player: FRadioPlayer, reason: FRadioPlayer.StallReason) {
        scheduleRetry()   // your backoff, which ends in retry()
    }

    func radioPlayer(_ player: FRadioPlayer, didFail failure: FRadioPlayer.Failure) {
        switch failure.kind {
        case .notFound, .decode: break          // terminal: tell the user
        default: scheduleRetry()
        }
    }

    func radioPlayer(_ player: FRadioPlayer, interruptionEnded shouldResume: Bool) {
        if shouldResume { player.play() }
    }

    func retry() {
        player.stop(discardingItem: true)   // reconnect, don't resume
        player.play()
    }
}
```

Notes:

- Callbacks arrive on the main actor. Don't drive the player from inside `didFail`; it runs before `.error` is published, so schedule the retry instead.
- The configurator runs on the main actor for every new item (URL change, `play()` after an error, `play()` after `stop(discardingItem: true)`), never for a reattached one. Don't retain the item. A stop, discard or URL change made inside the configurator wins: that item is dropped, not attached. The same holds for one made from the `.loading` callback of the rebuild that follows `stop(discardingItem: true)`. Metadata already queued for a discarded or replaced item is dropped.
- Switching `recoveryPolicy` to `.hostManaged` cancels a reload the library already scheduled.

## Usage

### Basics

1. Import `FRadioPlayer`

```swift
import FRadioPlayer
```

2. Get the singleton `FRadioPlayer` instance

```swift
let player = FRadioPlayer.shared
```

3. Observe player events (optional)

```swift
final class MyObserver: NSObject, FRadioPlayerObserver {
    override init() {
        super.init()
        FRadioPlayer.shared.addObserver(self)
    }

    func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State) {
        // handle state change
    }
}
```

4. Set the radio URL
```swift
player.radioURL = URL(string: "http://example.com/station.mp3")
```

### Properties

- `isAutoPlay: Bool` Auto-play when `radioURL` is set (default `true`).
- `enableArtwork: Bool` Fetch album artwork via iTunes API (default `true`).
- `artworkAPI: FRadioArtworkAPI` Artwork provider, default `iTunesAPI(artworkSize: 300)`.
- `rate: Float?` Current `AVPlayer` rate.
- `isPlaying: Bool` Convenience read-only state.
- `state: FRadioPlayer.State` Player state.
- `playbackState: FRadioPlayer.PlaybackState` Playback state.
- `volume: Float?` Player volume, 0.0…1.0.
- `httpHeaderFields: [String:String]?` HTTP headers for the underlying `AVURLAsset`.
- `metadataExtractor: FRadioMetadataExtractor` Strategy to parse timed metadata.
- `currentMetadata: FRadioPlayer.Metadata?` Last parsed timed metadata.
- `currentArtworkURL: URL?` Last resolved artwork URL.
- `duration: TimeInterval` Total duration, 0 for live streams.
- `currentTime: Double` Current playback time in seconds.
- `FRadioPlayer.configuresAudioSession: Bool` (static) Whether the player sets the audio session category, default `true`. See [Audio session](#audio-session).

### Playback controls

- Play
```swift
player.play()
```

- Pause
```swift
player.pause()
```

- Stop
```swift
player.stop()
```

- Toggle playing state
```swift
player.togglePlaying()
```

- Seek (files with a known duration)
```swift
player.seek(to: 30) {
    // Called exactly once, on the main actor
}
```

The completion is always called exactly once, on the main actor, after `seek` returns. That includes a live stream or an item whose duration isn't known yet (no seek happens), no loaded item, and a seek that is superseded by a newer one. Seeking keeps the playback intent: a playing player keeps playing, a paused or stopped player stays that way, and a pause issued while the seek is in flight wins.

For live streams, `pause()` keeps the item attached and resumes from the buffered position. `stop()` detaches the item and clears metadata and artwork, but keeps the item: the next `play()` reattaches that same item, it does not build a new one. To reconnect with a fresh asset and item, call `stop(discardingItem: true)` before `play()`.

### Observer methods

- Player state
```swift
func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayer.State)
```

- Playback state
```swift
func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlayer.PlaybackState)
```

- Item change
```swift
func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?)
```

- Timed metadata
```swift
func radioPlayer(_ player: FRadioPlayer, metadataDidChange metadata: FRadioPlayer.Metadata?)
```

- Artwork URL
```swift
func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?)
```

- Duration and time updates
```swift
func radioPlayer(_ player: FRadioPlayer, durationDidChange duration: TimeInterval)
func radioPlayer(_ player: FRadioPlayer, playTimeDidChange currentTime: TimeInterval, duration: TimeInterval)
```

## Swift Radio App

For more complete app features, check out [Swift Radio App](https://github.com/analogcode/Swift-Radio-Pro) based on **FRadioPlayer**

<p align="center">
    <img alt="Swift Radio" src="Assets/swift-radio.jpg">
</p>

## Development

This repository uses Swift Package Manager for building and testing:

```sh
swift build
swift test
```

The test suite covers the public API contract, metadata extraction, the artwork API (stubbed, no network), playback against bundled fixtures, and state machine regressions. CI runs it on macOS and on an iOS simulator for pull requests, pushes to `main` and tags. Bug fixes should come with a failing test first.

## Author

[@fethica](https://fethica.com)

## License

FRadioPlayer is available under the MIT license. See the LICENSE file for more info.
