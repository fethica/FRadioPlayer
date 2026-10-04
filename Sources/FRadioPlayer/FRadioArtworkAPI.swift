//
//  FRadioArtworkAPI.swift
//  FRadioPlayer
//
//  Created by Fethi El Hassasna on 2017-11-25.
//  Copyright © 2017 Fethi El Hassasna (@fethica). All rights reserved.
//

import Foundation

/// Artwork lookup for the current metadata. The completion may be called on
/// any queue; the player hops it back to the main actor. The requirement is
/// `@preconcurrency` so conformers written before 0.4.0 keep compiling.
public protocol FRadioArtworkAPI {
    @preconcurrency
    func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping @Sendable (_ artworkURL: URL?) -> Void)
}
