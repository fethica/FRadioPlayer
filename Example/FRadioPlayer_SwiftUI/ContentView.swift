//
//  InfoPaneView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/4/20.
//  Copyright © 2020 FRadioPlayer Contributors. All rights reserved.
//

import SwiftUI
import FRadioPlayer

struct ContentView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        VStack {
            StationsListView().environmentObject(radioPlayer)
            Spacer()
            VStack(spacing: 0) {
                #if !targetEnvironment(macCatalyst)
                if radioPlayer.radio.playerState != .urlNotSet {
                    NowPlayingView().environmentObject(radioPlayer)
                }
                #endif
                StateView().environmentObject(radioPlayer)
                TabIconsView().environmentObject(radioPlayer)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioPlayer()
        
        ContentView()
            .environmentObject(state)
            .preferredColorScheme(.light)
    }
}
