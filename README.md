<p align="center">
<img alt="FRadioPlayer" src="https://fethica.com/assets/img/web/repo-hero.png" width="749">
</p>

# FRadioPlayer

[![CI Status](https://github.com/fethica/FRadioPlayer/workflows/Swift/badge.svg)](https://github.com/fethica/FRadioPlayer/actions?query=workflow%3ASwift)

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
- [x] Swift 5.5+
- [x] Network interruptions handling
- [x] Support for macOS
- [x] Support for tvOS
- [x] Support for Swift Package Manager SPM
- [ ] Support for Audio Taps
- [ ] Support for Audio Recording

## Requirements
- macOS 10.12+
- iOS 10.0+
- tvOS 10.0+
- Xcode 13+
- Swift 5.5+

## Installation

### Swift Package Manager

FRadioPlayer is available through [SPM](https://github.com/apple/swift-package-manager). To add it in Xcode: File > Add Packages… and use the URL of this repository. Or add the dependency in `Package.swift`:

```text
.package(url: "https://github.com/fethica/FRadioPlayer.git", branch: "master")
```

## Quick Start

Add the package, then use the shared player and observe changes.

```swift
import FRadioPlayer

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

// Elsewhere
FRadioPlayer.shared.togglePlaying()   // Play/Pause
FRadioPlayer.shared.stop()            // Stop
FRadioPlayer.shared.volume = 0.8      // Set volume (0.0...1.0)
```

### Manual

Prefer SPM. If needed, drag `Sources/FRadioPlayer` into your Xcode project.

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
    <img alt="Swift Radio" src="https://fethica.com/assets/img/web/swift-radio.jpg">
</p>

## Development

This repository uses Swift Package Manager for building and testing:

```sh
swift build
swift test
```

## Author

[Fethi El Hassasna](https://twitter.com/fethica)

## License

FRadioPlayer is available under the MIT license. See the LICENSE file for more info.
