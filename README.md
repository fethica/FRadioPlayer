<p align="center">
<img alt="FRadioPlayer" src="https://fethica.com/assets/img/web/repo-hero.png" width="749">
</p>

# FRadioPlayer

[![CI Status](http://img.shields.io/travis/fethica/FRadioPlayer.svg?style=flat)](https://travis-ci.org/fethica/FRadioPlayer)
[![Version](https://img.shields.io/cocoapods/v/FRadioPlayer.svg?style=flat)](http://cocoapods.org/pods/FRadioPlayer)
[![License](https://img.shields.io/cocoapods/l/FRadioPlayer.svg?style=flat)](http://cocoapods.org/pods/FRadioPlayer)
[![Platform](https://img.shields.io/cocoapods/p/FRadioPlayer.svg?style=flat)](http://cocoapods.org/pods/FRadioPlayer)

FRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

<p align="center">
    <img alt="FRadioPlayer" src="https://fethica.com/assets/img/web/fradioplayer-example.png" width="485">
</p>

## Features
- [x] Support internet radio URL playback
- [x] Update and parse track metadata
- [x] Update and show album artwork (via iTunes API)
- [x] Automatic handling of interruptions
- [x] Automatic handling of route changes
- [x] Support bluetooth playback
- [x] Swift 5
- [x] [Full documentation](https://fethica.github.io/FRadioPlayer/)
- [x] Network interruptions handling
- [x] Support for Carthage
- [x] Support for macOS
- [x] Support for tvOS
- [x] Support for Swift Package Manager SPM
- [ ] Support for Audio Taps
- [ ] Support for Audio Recording

## Requirements
- macOS 10.12+
- iOS 10.0+
- tvOS 10.0+
- Xcode 10.2+
- Swift 5

## Installation

### CocoaPods

FRadioPlayer is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'FRadioPlayer'
```

### Carthage

FRadioPlayer is available through [Carthage](https://github.com/Carthage/Carthage). To install it, simply add the following line to your Cartfile:

```text
github "fethica/FRadioPlayer" ~> 0.1.10
```

### Swift Package Manager

FRadioPlayer is available through [SPM](https://github.com/apple/swift-package-manager). To install it, simply add the following dependency to your `Package.swift` file:

```text
.package(url: "https://github.com/fethica/FRadioPlayer.git", from: "0.1.18")
```

### Manual

Drag the `Source` folder into your project.

## Usage

### Basics

1. Import `FRadioPlayer` (if you are using Cocoapods)

```swift
import FRadioPlayer
```

2. Get the singleton `FRadioPlayer` instance

```swift
let player = FRadioPlayer.shared
```

3. Set the delegate for the player

```swift
player.delegate = self
```

4. Set the radio URL
```swift
player.radioURL = URL(string: "http://example.com/station.mp3")
```

### Properties

- `isAutoPlay: Bool` The player starts playing when the `radioURL` property gets set. (default == `true`)

- `enableArtwork: Bool` Enable fetching albums artwork from the iTunes API. (default == `true`)

- `artworkSize: Int` Artwork image size. (default == `100` | 100x100).

- `rate: Float?` Read only property to get the current `AVPlayer` rate.

- `isPlaying: Bool` Read only property to check if the player is playing.

- `state: FRadioPlayerState` Player current state of type `FRadioPlayerState`.

- `playbackState: FRadioPlaybackState` Playing state of type `FRadioPlaybackState`.

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

### Delegate methods

Called when player changes state
```swift
func radioPlayer(_ player: FRadioPlayer, playerStateDidChange state: FRadioPlayerState)
```

Called when the playback changes state
```swift
func radioPlayer(_ player: FRadioPlayer, playbackStateDidChange state: FRadioPlaybackState)
```

Called when player changes the current player item
```swift
func radioPlayer(_ player: FRadioPlayer, itemDidChange url: URL?)
```

Called when player item changes the timed metadata value
```swift
func radioPlayer(_ player: FRadioPlayer, metadataDidChange artistName: String?, trackName: String?)
```

Called when player item changes the timed metadata value
```swift
func radioPlayer(_ player: FRadioPlayer, metadataDidChange rawValue: String?)
```

Called when the player gets the artwork for the playing song
```swift
func radioPlayer(_ player: FRadioPlayer, artworkDidChange artworkURL: URL?)
```

## Swift Radio App

For more complete app features, check out [Swift Radio App](https://github.com/analogcode/Swift-Radio-Pro) based on **FRadioPlayer**

<p align="center">
    <img alt="Swift Radio" src="https://fethica.com/assets/img/web/swift-radio.jpg">
</p>

## Hacking

The Xcode project is generated automatically from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). It's only checked in because Carthage needs it, do not edit it manually.

```sh
$ mint run yonaskolb/xcodegen
💾  Saved project to FRadioPlayer.xcodeproj
```

## Author

[Fethi El Hassasna](https://twitter.com/fethica)

## License

FRadioPlayer is available under the MIT license. See the LICENSE file for more info.
