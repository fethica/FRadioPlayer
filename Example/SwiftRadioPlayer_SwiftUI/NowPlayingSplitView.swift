//
//  NowPlayingSplitView.swift
//  SwiftRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/6/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI

struct NowPlayingSplitView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        VStack(spacing: 16) {
            VStack {
                Image(uiImage: radioPlayer.radio.track.image ?? #imageLiteral(resourceName: "albumArt"))
                    .resizable()
                    .foregroundColor(Color.secondary)
                    .scaledToFit()
                    .frame(width: 400, height: 400)
                
            }.padding(.leading, 10)
            
            Text(radioPlayer.radio.track.name ?? "")
                .font(.title)
                .lineLimit(1)
                .allowsTightening(true)
                .padding(.trailing, 0)
            
            
            Text(radioPlayer.radio.track.artist ?? "")
                .font(.title2)
                .lineLimit(1)
                .allowsTightening(true)
                .padding(.trailing, 0)
            
            Spacer()
            
            AirPlayView()
                .frame(width: 50, height: 50)
        }
    }
}

struct NowPlayingViewSplit_Previews: PreviewProvider {
    static var previews: some View {
        let radioPlayer = RadioPlayer()

        NowPlayingSplitView()
            .environmentObject(radioPlayer)
            .preferredColorScheme(.dark)
    }
}
