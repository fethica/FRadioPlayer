//
//  TabIconsView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/4/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import FRadioPlayer

struct TabIconsView: View {
    
    @EnvironmentObject var state: RadioDelegateClass
    
    var body: some View {
        HStack {
            Spacer()
            
            Button(action: {
                // your action here
                print("Backward")
                state.currentIndex -= 1
            }) {
                Image(systemName: "backward.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
            Button(action: {
                // your action here
                print("Play Pause From Tab Icons")
                tooglePlayback()
            }) {
                Image(systemName: state.playbackImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
            Button(action: {
                // your action here
                print("Stop From Tab Icons")
                stopPlayback()
            }) {
                Image(systemName:"stop.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
            }
            
            Spacer()
            
            Button(action: {
                // your action here
                print("Forward")
                state.currentIndex += 1
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
    
    func tooglePlayback() {
        print("IS PLAYING?: \(state.radioPlayerShared.isPlaying)")
        if state.radioPlayerShared.isPlaying {
            state.radioPlayerShared.pause()
        } else {
            state.radioPlayerShared.play()
        }
    }
    
    func stopPlayback() {
        state.radioPlayerShared.stop()
    }
}

struct TabIconsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioDelegateClass()

        TabIconsView()
            .environmentObject(state)
            .preferredColorScheme(.dark)
    }
}
