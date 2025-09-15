//
//  NowPlayingView.swift
//  FRadioPlayerDemo
//
//  Created by Urayoan Miranda on 12/4/20.
//  Copyright © 2020 FRadioPlayer Contributors. All rights reserved.
//

import SwiftUI

struct NowPlayingView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        HStack {
            if let url = radioPlayer.radio.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Image(radioPlayer.radio.currentStationImageName ?? "albumArt").resizable()
                }
                .scaledToFit()
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            } else {
                Image(radioPlayer.radio.currentStationImageName ?? "albumArt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 8, content: {
                
                Text(radioPlayer.radio.track.name ?? "")
                    .font(.body)
                    .bold()
                    .lineLimit(1)
                    .allowsTightening(true)
                    
                Text(radioPlayer.radio.track.artist ?? "")
                    .font(.footnote)
                    .lineLimit(1)
                    .allowsTightening(true)
            })
                        
            Spacer()
            
            AirPlayView()
                .frame(width: 50, height: 50)
        }
        .padding(.all, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioPlayer()
        NowPlayingView()
            .environmentObject(state)
            .preferredColorScheme(.dark)
    }
}
