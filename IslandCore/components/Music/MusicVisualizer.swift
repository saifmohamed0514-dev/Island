//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import SwiftUI

// The compatibility view uses real opt-in audio capture instead of random bars.
struct AudioSpectrumView:View {
    @Binding var isPlaying:Bool
    var body:some View { IslandLiveWaveform(playing:isPlaying) }
}
