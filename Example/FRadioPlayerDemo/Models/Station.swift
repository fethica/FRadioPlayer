//
//  Station.swift
//  FRadioPlayerDemo
//
//  Created by Fethi El Hassasna on 2017-11-25.
//  Copyright © 2017 Fethi El Hassasna. All rights reserved.
//

import Foundation


struct Station: Identifiable, Hashable {
    var id = UUID()
    let name: String
    let detail: String
    let url: URL
    let imageName: String?
    
    init(name: String, detail: String, url: URL, imageName: String? = nil) {
        self.name = name
        self.detail = detail
        self.url = url
        self.imageName = imageName
    }
}
