//
//  FRadioArtworkAPI.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2017-11-25.
//  Copyright © 2017 Fethi El Hassasna (@fethica). All rights reserved.
//

import Foundation

public protocol FRadioArtworkAPI {
    func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping (_ artworkURL: URL?) -> Void)
}
