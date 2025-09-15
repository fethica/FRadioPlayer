//
//  AirPlayView.swift
//  FRadioPlayerDemo
//
//  Created by Demo.
//

import SwiftUI
import AVKit
import UIKit

struct AirPlayView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView(frame: .zero)
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = .label
        view.activeTintColor = .label
    }
}
