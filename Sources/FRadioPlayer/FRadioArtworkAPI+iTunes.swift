//
//  FRadioArtworkAPI+iTunes.swift
//  Pods
//
//  Created by Fethi El Hassasna on 2021-10-19.
//

import Foundation
import UIKit

// MARK: - iTunes API
public struct iTunesAPI: FRadioArtworkAPI {
    
    let artworkSize: Int
    private let session: URLSession
    
    public init(artworkSize: Int, session: URLSession = URLSession.shared) {
        self.artworkSize = artworkSize
        self.session = session
    }
    
    public func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping (URL?) -> Void) {
        
        guard !metadata.isEmpty, let rawValue = metadata.rawValue, let url = getURL(with: rawValue) else {
            completion(nil)
            return
        }
        
        let task = session.dataTask(with: url) { (data, response, error) in
            guard error == nil, let data = data else {
                completion(nil)
                return
            }
                        
            guard let response = try? JSONDecoder().decode(iTunesResponse.self, from: data), let artworkURL = response.results.first?.artworkURL(for: artworkSize) else {
                completion(nil)
                return
            }
            
            completion(artworkURL)
        }
        
        task.resume()
    }
    
    
    // MARK: - Util methods
    private func getURL(with term: String) -> URL? {
        var components = URLComponents()
        components.scheme = Domain.scheme
        components.host = Domain.host
        components.path = Domain.path
        components.queryItems = [URLQueryItem]()
        components.queryItems?.append(URLQueryItem(name: Keys.term, value: term))
        components.queryItems?.append(URLQueryItem(name: Keys.entity, value: Values.entity))
        return components.url
    }
    
}

extension iTunesAPI {

    // MARK: - Constants
    private struct Domain {
        static let scheme = "https"
        static let host = "itunes.apple.com"
        static let path = "/search"
    }
    
    private struct Keys {
        // Request
        static let term = "term"
        static let entity = "entity"
    }
    
    private struct Values {
        static let entity = "song"
    }
}

private struct iTunesResponse: Decodable {
    let results: [TrackResult]
    
    struct TrackResult: Decodable {
        private let artworkUrl100: String
                
        func artworkURL(for size: Int) -> URL? {
            var artwork = artworkUrl100
            
            if size != 100, size > 0 {
                artwork = artwork.replacingOccurrences(of: "100x100", with: "\(size)x\(size)")
            }
            
            return URL(string: artwork)
        }
    }
}
