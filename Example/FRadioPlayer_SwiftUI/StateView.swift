//
//  StateView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Fethi El Hassasna on 2020-12-09.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import FRadioPlayer

struct StateView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        HStack {
            Text("Player State")
                .font(.footnote)
                .foregroundColor(.white)
                .bold()
            Spacer()
            Text(radioPlayer.radio.playerState.description)
                .font(.footnote)
                .foregroundColor(.white)
                .bold()
        }
        .padding(8)
        .background(Color(red: 51/255, green: 73/255, blue: 95/255, opacity: 1))
        
    }
}

struct StateView_Previews: PreviewProvider {
    static var previews: some View {
        StateView()
            .environmentObject(RadioPlayer())
    }
}
