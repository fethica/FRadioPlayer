//
//  AirPlayView.swift
//  FRadioPlayer_SwiftUI
//
//  Created by Urayoan Miranda on 12/6/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import SwiftUI
import UIKit
import AVKit

struct AirPlayView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView(frame: .zero)
    }
    
    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor          = .gray
        view.activeTintColor    = UIColor(red: 0, green: 189/255, blue: 233/255, alpha: 1)
    }
}

struct AirPlayView_Previews: PreviewProvider {
    static var previews: some View {
        AirPlayView()
    }
}
