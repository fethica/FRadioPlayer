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
    
    public init(artworkSize: Int) {
        self.artworkSize = artworkSize
    }
    
    public func getArtwork(for metadata: FRadioPlayer.Metadata, _ completion: @escaping (URL?) -> Void) {
        
        guard !metadata.isEmpty, let rawValue = metadata.rawValue, let url = getURL(with: rawValue) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
            guard error == nil, let data = data else {
                completion(nil)
                return
            }
            
            // Replace with Codable
            let json = try? JSONSerialization.jsonObject(with: data, options: .allowFragments)
            
            guard let parsedResult = json as? [String: Any],
                let results = parsedResult[Keys.results] as? Array<[String: Any]>,
                let result = results.first,
                var artwork = result[Keys.artwork] as? String else {
                    completion(nil)
                    return
            }
                        
            if artworkSize != 100, artworkSize > 0 {
                artwork = artwork.replacingOccurrences(of: "100x100", with: "\(artworkSize)x\(artworkSize)")
            }
            
            let artworkURL = URL(string: artwork)
            completion(artworkURL)
        }).resume()
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
        
        // Response
        static let results = "results"
        static let artwork = "artworkUrl100"
    }
    
    private struct Values {
        static let entity = "song"
    }
}
