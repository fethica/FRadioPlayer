//
//  TabIconsView.swift
//  FRadioPlayerDemo
//
//  Created by Urayoan Miranda on 12/4/20.
//  Copyright © 2020 FRadioPlayer Contributors. All rights reserved.
//

import SwiftUI

struct TabIconsView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        HStack {
            Spacer()
            
            Button(action: {
                radioPlayer.currentIndex -= 1
            }) {
                Image(systemName: "backward.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
            Button(action: {
                radioPlayer.player.togglePlaying()
            }) {
                Image(systemName: radioPlayer.radio.playbackState == .playing ? "pause.fill" : "play.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
            Button(action: {
                radioPlayer.player.stop()
            }) {
                Image(systemName:"stop.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
            Button(action: {
                radioPlayer.currentIndex += 1
            }) {
                Image(systemName: "forward.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
        }.padding(16)
        .foregroundColor(.primary)
    }
}

struct TabIconsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioPlayer()

        TabIconsView()
            .environmentObject(state)
            .preferredColorScheme(.dark)
    }
}
