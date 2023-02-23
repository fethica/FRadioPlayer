//
//  NowPlayingView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/4/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import FRadioPlayer

struct NowPlayingView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        HStack {
            Image(uiImage: radioPlayer.radio.track.image ?? #imageLiteral(resourceName: "albumArt"))
                .resizable()
                .foregroundColor(Color.secondary)
                .scaledToFit()
                .frame(width: 50, height: 50)
            
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

