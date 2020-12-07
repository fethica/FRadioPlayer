//
//  ContentView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/3/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import Combine
import FRadioPlayer

struct StationsList: View {
    
    @EnvironmentObject var state: RadioDelegateClass
    
    var body: some View {
        NavigationView {
            List(state.stations.indices, id: \.self) { index in
                    HStack {
                        Button(action: {
                            // your action here
                            print("\(state.stations[index].url)")
                            state.stationDidChange(station: state.stations[index])
                        }) {
                            Image(uiImage: state.stations[index].image!)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                        }
                        Text("\(state.stations[index].name)")
                        Spacer()
                    }
            }.navigationBarTitle("FRadio Player", displayMode: .automatic)
            
            #if targetEnvironment(macCatalyst)
                NowPlayingViewSplit()
            #endif
        }
    }
}


struct StationsList_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioDelegateClass()

        StationsList()
            .environmentObject(state)
            .preferredColorScheme(.light)
    }
}
