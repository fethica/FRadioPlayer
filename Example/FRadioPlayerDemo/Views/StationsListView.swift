//
//  ContentView.swift
//  FRadioPlayerDemo
//
//  Created by Urayoan Miranda on 12/3/20.
//  Copyright © 2020 FRadioPlayer Contributors. All rights reserved.
//

import SwiftUI

struct StationsListView: View {
    
    @EnvironmentObject var radioPlayer: RadioPlayer
    
    var body: some View {
        NavigationView {
            List(radioPlayer.stations.indices, id: \.self) { index in
                Button(action: { radioPlayer.currentIndex = index }) {
                    HStack(spacing: 12) {
                        Image(radioPlayer.stations[index].imageName ?? "albumArt")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .cornerRadius(8)
                            .clipped()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(radioPlayer.stations[index].name).font(.headline)
                            Text(radioPlayer.stations[index].detail).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("FRadioPlayer")
        }
    }
}


struct StationsList_Previews: PreviewProvider {
    static var previews: some View {
        let state = RadioPlayer()

        StationsListView()
            .environmentObject(state)
            .preferredColorScheme(.light)
    }
}
