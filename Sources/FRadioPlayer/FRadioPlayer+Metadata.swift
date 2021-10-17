//
//  FRadioPlayer+Metadata.swift
//  Pods
//
//  Created by Fethi El Hassasna on 2021-10-16.
//

import AVFoundation

public extension FRadioPlayer {
    struct Metadata {
        public let artistName: String?
        public let trackName: String?
        public let rawValue: String?
        public var groups: [AVTimedMetadataGroup]
                
        public var isEmpty: Bool {
            (artistName == nil) && (trackName == nil) && (groups.isEmpty)
        }
    }
}
