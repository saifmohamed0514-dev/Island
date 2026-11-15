//
//  IslandPanel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class IslandPanel: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var hideForFullscreen=false
    func bindVisibility(to model:IslandViewModel) {
        Publishers.CombineLatest(model.$hideOnClosed,model.$notchState).receive(on:DispatchQueue.main).sink { [weak self] fullscreen,state in
            self?.hideForFullscreen=fullscreen && state == .closed;self?.updateFullscreenVisibility()
        }.store(in:&observers)
    }
    private func updateFullscreenVisibility() { let hidden=hideForFullscreen && !isSkyLightEnabled;ignoresMouseEvents=hidden;alphaValue=hidden ? 0 : 1 }
    // AppKit otherwise reserves a one-point strip above floating panels.
    // Island is positioned explicitly against the physical display edge.
    override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?)->NSRect { frameRect }
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Inherit system appearance; only the black Island surface uses dark content.
        appearance = nil
        
        updateCollectionBehavior()
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func updateCollectionBehavior() {
        collectionBehavior=[.fullScreenAuxiliary,.canJoinAllSpaces,.ignoresCycle,UserDefaults.standard.bool(forKey:"island.visibility.missionControl") ? .transient : .stationary]
    }
    private func setupObservers() {
        NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification).receive(on:DispatchQueue.main).sink { [weak self] _ in self?.updateCollectionBehavior() }.store(in:&observers)
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
            updateFullscreenVisibility()
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
            updateFullscreenVisibility()
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
