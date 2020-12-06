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
    
    @EnvironmentObject var state: RadioDelegateClass
    
    var body: some View {
        Divider()
        HStack(spacing: 16) {
            ZStack {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 50, height: 50)
                    .cornerRadius(5)
                    .shadow(radius: 5)
                
                Image(uiImage: (state.metadata.image ?? UIImage(named: "albumArt"))!)
                    .resizable()
                    .foregroundColor(Color.secondary)
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                
            }.padding(.leading, 10)
            
            Text("\(state.artist) \(state.name)")
                .lineLimit(1)
                .allowsTightening(true)
                .padding(.trailing, 0)
            
            Spacer()
            
            AirPlayView()
                .frame(width: 50, height: 50)
        }
    }
}

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioDelegateClass()
        NowPlayingView()
            .environmentObject(state)
            .preferredColorScheme(.dark)
    }
}

