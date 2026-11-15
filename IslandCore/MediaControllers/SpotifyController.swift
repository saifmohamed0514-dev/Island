//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class SpotifyController: MediaControllerProtocol {
    private let capabilities=IslandPlayerCapabilities.spotify()
    var supportsPlaybackRate:Bool { capabilities.speedProperty != nil }
    func setPlaybackRate(_ value:Double) async { guard let property=capabilities.speedProperty,value.isFinite,(0.5...3).contains(value) else { return };await executeAndRefresh("set "+property+" to "+String(value)) }
    func setFavorite(_ favorite: Bool) async {
        guard let property=capabilities.favoriteProperty else { return }
        await executeAndRefresh("set "+property+" of current track to "+(favorite ? "true" : "false"))
    }
    
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { capabilities.favoriteProperty != nil }

    private var notificationTask: Task<Void, Never>?
    
    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    
    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }
    func previousTrack() async {
        await executeAndRefresh("previous track")
    }
    
    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }
    
    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }
    
    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 10 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(10)?.stringValue ?? ""
        
        var state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(volumePercentage) / 100.0
        )

        if descriptor.numberOfItems>=14 {
            state.trackURL=IslandTrackLink.safe(descriptor.atIndex(11)?.stringValue)
            state.isFavorite=descriptor.atIndex(12)?.booleanValue ?? false
            state.isExplicit=capabilities.explicitProperty == nil ? nil : descriptor.atIndex(13)?.booleanValue
            let rate=descriptor.atIndex(14)?.doubleValue ?? 1;state.playbackRate=rate.isFinite && (0.5...3).contains(rate) ? rate : 1
        }
        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

    playbackState = state

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let currentState = state

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        guard !Task.isCancelled,self.playbackState.title == currentState.title,self.playbackState.artist == currentState.artist,self.playbackState.album == currentState.album else { return }
                        var updatedState = self.playbackState
                        updatedState.artwork = data
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }
    
// MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script,permissionTarget:"com.spotify.client")
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let favoriteRead=capabilities.favoriteProperty.map { "try\nset favoriteValue to "+$0+" of current track\nend try" } ?? ""
        let explicitRead=capabilities.explicitProperty.map { "try\nset explicitValue to "+$0+" of current track\nend try" } ?? ""
        let speedRead=capabilities.speedProperty.map { "try\nset speedValue to "+$0+"\nend try" } ?? ""
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                set linkValue to ""
                set favoriteValue to false
                set explicitValue to false
                set speedValue to 1
                try
                    set linkValue to spotify url of current track
                end try
                \(favoriteRead)
                \(explicitRead)
                \(speedRead)
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL, linkValue, favoriteValue, explicitValue, speedValue}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, 50, ""}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script,permissionTarget:"com.spotify.client")
    }
    
}
