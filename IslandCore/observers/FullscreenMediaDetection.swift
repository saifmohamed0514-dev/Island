//
//  FullscreenMediaDetection.swift
//  boringNotch
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Foundation
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    
    @Published var fullscreenStatus: [String: Bool] = [:]
    
    private var monitorTask: Task<Void, Never>?
    private var lastSpaces:[MacroVisionKit.FullScreenMonitor.SpaceInfo]=[]
    private var subscriptions=Set<AnyCancellable>()
    
    private init() {
        startMonitoring()
        Task { @MainActor [weak self] in
            guard let self else { return }
            Defaults.publisher(.hideNotchOption).sink { [weak self] _ in guard let self else { return };self.updateStatus(with:self.lastSpaces) }.store(in:&self.subscriptions)
            MusicManager.shared.$bundleIdentifier.removeDuplicates().receive(on:RunLoop.main).sink { [weak self] _ in guard let self else { return };self.updateStatus(with:self.lastSpaces) }.store(in:&self.subscriptions)
        }
    }
    
    deinit {
        monitorTask?.cancel()
    }
    
    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }
    
    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        lastSpaces=spaces
        var newStatus: [String: Bool] = [:]
        
        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier  {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }
        
        self.fullscreenStatus = newStatus
    }
}

