//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

enum RepeatMode: Int, Codable {
    case off = 1
    case one = 2
    case all = 3
}

struct PlaybackState {
    var bundleIdentifier: String
    var isPlaying: Bool = false
    var title: String = "Not Playing"
    var artist: String = ""
    var album: String = ""
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false
    var supportsForward15=false
    var supportsBackward15=false
    var prohibitsSkip=false
    var shuffleAvailable=false
    var repeatAvailable=false
    var isExplicit:Bool?
    var trackURL:URL?
}

extension PlaybackState: Equatable {
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.currentTime == rhs.currentTime
            && lhs.duration == rhs.duration
            && lhs.playbackRate == rhs.playbackRate
            && lhs.volume == rhs.volume
            && lhs.lastUpdated == rhs.lastUpdated
            && lhs.supportsForward15 == rhs.supportsForward15
            && lhs.supportsBackward15 == rhs.supportsBackward15
            && lhs.prohibitsSkip == rhs.prohibitsSkip
            && lhs.shuffleAvailable == rhs.shuffleAvailable
            && lhs.repeatAvailable == rhs.repeatAvailable
            && lhs.isExplicit == rhs.isExplicit
            && lhs.trackURL == rhs.trackURL
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && lhs.artwork == rhs.artwork
            && lhs.isFavorite == rhs.isFavorite
    }
}
