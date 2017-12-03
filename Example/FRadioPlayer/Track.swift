//
//  Track.swift
//  FRadioPlayerDemo
//
//  Created by Fethi El Hassasna on 2017-12-03.
//  Copyright © 2017 Fethi El Hassasna. All rights reserved.
//

import UIKit

struct Track {
    var artist: String?
    var name: String?
    var image: UIImage?
    
    init(artist: String? = nil, name: String? = nil, image: UIImage? = nil) {
        self.name = name
        self.artist = artist
        self.image = image
    }
}
