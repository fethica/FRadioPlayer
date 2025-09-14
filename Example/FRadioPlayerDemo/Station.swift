//
//  Station.swift
//  FRadioPlayerDemo
//
//  Created by Fethi El Hassasna on 2017-11-25.
//  Copyright © 2017 Fethi El Hassasna. All rights reserved.
//

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(OSX)
import Cocoa
#endif


struct Station: Identifiable, Hashable {
    var id = UUID()
    let name: String
    let detail: String
    let url: URL
    #if os(iOS) || os(tvOS)
    var image: UIImage?
    #elseif os(OSX)
    var image: NSImage?
    #endif
    
    #if os(iOS) || os(tvOS)
    init(name: String, detail: String, url: URL, image: UIImage? = nil) {
        self.name = name
        self.detail = detail
        self.url = url
        self.image = image
    }
    #elseif os(OSX)
    init(name: String, detail: String, url: URL, image: NSImage? = nil) {
        self.name = name
        self.detail = detail
        self.url = url
        self.image = image
    }
    #endif
}
