//
//  FRadioPlayer+Metadata.swift
//  Pods
//
//  Created by Fethi El Hassasna on 2021-10-16.
//

import Foundation

public extension FRadioPlayer {
    struct Metadata {
        public let artistName: String?
        public let trackName: String?
        public var attributes = [String: Any]()
                
        public var isEmpty: Bool {
            (artistName == nil) && (trackName == nil) && (attributes.isEmpty)
        }
    }
}
