//
//  Track.swift
//  FRadioPlayerDemo
//
//  Created by Fethi El Hassasna on 2017-12-03.
//  Copyright © 2017 Fethi El Hassasna. All rights reserved.
//

#if os(iOS)
import UIKit
#elseif os(OSX)
import Cocoa
#endif


struct Track {
    var artist: String?
    var name: String?
    
    #if os(iOS)
    var image: UIImage?
    #elseif os(OSX)
    var image: NSImage?
    #endif
    
    #if os(iOS)
    init(artist: String? = nil, name: String? = nil, image: UIImage? = nil) {
        self.name = name
        self.artist = artist
        self.image = image
    }
    #elseif os(OSX)
    init(artist: String? = nil, name: String? = nil, image: NSImage? = nil) {
        self.name = name
        self.artist = artist
        self.image = image
    }
    #endif
}
