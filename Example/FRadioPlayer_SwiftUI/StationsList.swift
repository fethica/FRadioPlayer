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
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        NavigationView {
            List(radioPlayer.stations.indices) { index in
                    HStack {
                        Button(action: {
                            radioPlayer.currentIndex = index
                        }) {
                            Image(uiImage: radioPlayer.stations[index].image ?? #imageLiteral(resourceName: "albumArt"))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(radioPlayer.stations[index].name).font(.title3)
                            Text(radioPlayer.stations[index].detail).font(.footnote)
                        }
                        .padding(.all, 8)
                    }
            }
            .navigationBarTitle("FRadioPlayer", displayMode: .automatic)
            
            #if targetEnvironment(macCatalyst)
                NowPlayingViewSplit()
            #endif
        }
    }
}


struct StationsList_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioPlayer()

        StationsList()
            .environmentObject(state)
            .preferredColorScheme(.light)
    }
}
