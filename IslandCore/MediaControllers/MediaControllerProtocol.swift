//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    var supportsShuffle:Bool { get }
    var supportsRepeat:Bool { get }
    var supportsPlaybackRate:Bool { get }
    func setPlaybackRate(_ value:Double) async
    
    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func shutdown()
    func updatePlaybackInfo() async
}

extension MediaControllerProtocol { func shutdown() {};var supportsShuffle:Bool { true };var supportsRepeat:Bool { true };var supportsPlaybackRate:Bool { false };func setPlaybackRate(_ value:Double) async {} }
