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
        public let groups: [AVTimedMetadataGroup]
                
        public var isEmpty: Bool {
            (artistName == nil) && (trackName == nil) && (groups.isEmpty)
        }
        
        public init?(groups: [AVTimedMetadataGroup]) {
            guard !groups.isEmpty else { return nil }
            
            let rawValue = groups.first?.items.first?.value as? String
            let rawValueCleaned = Metadata.cleanRawMetadataIfNeeded(rawValue)
            let parts = rawValueCleaned?.components(separatedBy: " - ")
            
            self.artistName = parts?.first
            self.trackName = parts?.last
            self.rawValue = rawValueCleaned
            self.groups = groups
        }
    }
}

private extension FRadioPlayer.Metadata {
    static func cleanRawMetadataIfNeeded(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue else { return nil }
        // Strip off trailing '[???]' characters left there by ShoutCast and Centova Streams
        // It will leave the string alone if the pattern is not there
        
        let pattern = #"(\(.*?\)\w*)|(\[.*?\]\w*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return rawValue }
        
        let rawCleaned = NSMutableString(string: rawValue)
        regex.replaceMatches(in: rawCleaned , options: .reportProgress, range: NSRange(location: 0, length: rawCleaned.length), withTemplate: "")
        
        return rawCleaned as String
    }
}
