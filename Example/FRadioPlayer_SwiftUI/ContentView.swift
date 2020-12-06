//
//  InfoPaneView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/4/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import FRadioPlayer

struct ContentView: View {
    
    @EnvironmentObject var state: RadioDelegateClass

    var body: some View {
        VStack(alignment: .trailing, spacing: 0.0) {
            StationsList().environmentObject(state)
            Spacer()
            ZStack {
                VStack {
                    NowPlayingView().environmentObject(state)
                    Divider()
                    TabIconsView().environmentObject(state)
                }
            }.frame(height: 160)
        }
        .edgesIgnoringSafeArea(.top)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioDelegateClass()

        ContentView()
            .environmentObject(state)
            .preferredColorScheme(.light)
    }
}
