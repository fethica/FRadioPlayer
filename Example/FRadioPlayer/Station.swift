//
//  Station.swift
//  FRadioPlayerDemo
//
//  Created by Fethi El Hassasna on 2017-11-25.
//  Copyright © 2017 Fethi El Hassasna. All rights reserved.
//

import UIKit

struct Station {
    let name: String
    let detail: String
    let url: URL
    var image: UIImage?
    
    init(name: String, detail: String, url: URL, image: UIImage? = nil) {
        self.name = name
        self.detail = detail
        self.url = url
        self.image = image
    }
}
