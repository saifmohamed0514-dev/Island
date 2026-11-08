//
//  IslandApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @ObservedObject private var snooze=IslandSnooze.shared
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = IslandUpdates.shared.controller

        // Initialize the settings window controller with the updater controller
        IslandSettingsController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("Island", systemImage: "capsule.fill", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    IslandSettingsController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Button(snooze.active ? "Resume Island" : "Snooze Island") { snooze.toggle() }
            Button("Set up Island…") { appDelegate.showOnboardingWindow() }
            CheckForUpdatesView(updater: updaterController.updater)
                .disabled(!IslandUpdateConfiguration.isConfigured)
            Divider()
            Button("Restart Island") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }.commands {
            CommandGroup(after:.appInfo) { Button("Open Island") { appDelegate.openIslandFromMenu() };Button("Set up Island…") { appDelegate.showOnboardingWindow() } }
            CommandGroup(replacing:.appSettings) {
                Button("Island Settings…") { IslandSettingsController.shared.showWindow() }
                    .keyboardShortcut(",",modifiers:.command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: IslandViewModel] = [:] // UUID -> IslandViewModel
    var window: NSWindow?
    let vm: IslandViewModel = .init()
    @ObservedObject var coordinator = IslandCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var snoozeObserver:AnyCancellable?
    private var setupObserver:NSObjectProtocol?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector

    func openIslandFromMenu() {
        IslandSnooze.shared.resume()
        closeNotchTask?.cancel(); closeNotchTask = nil
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let selected = screen?.displayUUID.flatMap { viewModels[$0] } ?? vm
        selected.open()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let setupObserver { NotificationCenter.default.removeObserver(setupObserver) }
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? IslandPanel {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? IslandPanel {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? IslandPanel {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? IslandPanel {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        guard !IslandSnooze.shared.active else { return }
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard IslandModuleStore.shared.enabled.contains(.shelf) else { return }
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createIslandLegacyWindow(for screen: NSScreen, with viewModel: IslandViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = IslandPanel(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        let hosting = NSHostingView(rootView: ContentView().environmentObject(viewModel))
        hosting.safeAreaRegions = []
        window.contentView = hosting

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index=CommandLine.arguments.firstIndex(of:"--relaunch-from-pid"),index+1<CommandLine.arguments.count,let pid=Int32(CommandLine.arguments[index+1]),NSRunningApplication(processIdentifier:pid)?.isTerminated == false {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { [weak self] in self?.applicationDidFinishLaunching(notification) };return
        }
        if let id = Bundle.main.bundleIdentifier, let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); NSApp.terminate(nil); return
        }
        setupObserver=NotificationCenter.default.addObserver(forName:.islandShowSetup,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.showOnboardingWindow() } }
        _ = IslandFocusTimer.shared
        IslandProfileSchedule.shared.start()
        IslandLiveActivityClock.shared.configure()
        if UserDefaults.standard.bool(forKey:"island.awake.restore") { IslandQuickActions.shared.setAwake(true) }
        IslandWindowSnapping.shared.configure()
        IslandUsageTracker.shared.setEnabled(IslandModuleStore.shared.enabled.contains(.usage))
        IslandDevices.shared.configure(IslandModuleStore.shared.enabled.contains(.devices))
        IslandWellbeingReminders.shared.configure(IslandModuleStore.shared.enabled.contains(.health))
        IslandAgentBridge.shared.start(IslandModuleStore.shared.enabled.contains(.agents) || IslandModuleStore.shared.enabled.contains(.inbox))


        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for:.islandSnooze) { IslandSnooze.shared.toggle() }
        KeyboardShortcuts.onKeyDown(for:.islandNextModule) { [weak self] in self?.navigateModule(1) }
        KeyboardShortcuts.onKeyDown(for:.islandPreviousModule) { [weak self] in self?.navigateModule(-1) }
        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }
                IslandSnooze.shared.resume()

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createIslandLegacyWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()
        snoozeObserver=IslandSnooze.shared.$active.dropFirst().receive(on:DispatchQueue.main).sink { [weak self] active in
            guard let self else { return }
            if active {
                self.window?.orderOut(nil);self.windows.values.forEach { $0.orderOut(nil) };self.cleanupDragDetectors()
            } else { self.adjustWindowPosition(changeAlpha:true);self.window?.orderFrontRegardless();self.windows.values.forEach { $0.orderFrontRegardless() };self.setupDragDetectors() }
        }

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }

        }

        if CommandLine.arguments.contains("--inspect-island") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }; self.vm.open(); self.viewModels.values.forEach { $0.open() }
            }
        }
        previousScreens = NSScreen.screens
    }

    private func navigateModule(_ direction:Int) {
        let open=vm.notchState == .open || viewModels.values.contains { $0.notchState == .open }
        guard !IslandSnooze.shared.active,!UserDefaults.standard.bool(forKey:"island.shortcuts.openOnly") || open else { return }
        let modules=IslandModuleStore.shared.enabled
        guard !modules.isEmpty else { return }
        let index=modules.firstIndex(of:coordinator.currentView) ?? 0
        coordinator.currentView=modules[(index+direction+modules.count)%modules.count]
        coordinator.showingCanvasDetail=coordinator.currentView != .dashboard
        IslandHaptics.play(.selection)
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        guard !IslandSnooze.shared.active else { return }
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = IslandViewModel(screenUUID: uuid)
                    let window = createIslandLegacyWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createIslandLegacyWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    func showOnboardingWindow(step:OnboardingStep = .welcome) {
        guard !IslandPermissionSetup.shared.prompting else { IslandSettingsController.shared.showWindow();return }
        if IslandPermissionSetup.shared.running { IslandPermissionSetup.shared.stop() }
        IslandSettingsController.shared.window?.orderOut(nil)
        IslandUpdates.shared.suspendForSetup()
        if let window=onboardingWindowController?.window {
            NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil);return
        }
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:740,height:700),styleMask:[.titled],backing:.buffered,defer:false)
        window.title="Set up Island";window.isReleasedWhenClosed=false;window.isRestorable=false
        window.identifier=NSUserInterfaceItemIdentifier("OnboardingWindow")
        window.contentView=NSHostingView(rootView:OnboardingView(step:step,onFinish:{ [weak self,weak window] in
            window?.orderOut(nil);window?.close();self?.onboardingWindowController=nil
            IslandUpdates.shared.resumeAfterSetup()
            NSApp.setActivationPolicy(.accessory)
        }))
        onboardingWindowController=NSWindowController(window:window)
        window.center();NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
    }

}

extension Notification.Name {
    static let islandShowSetup=Notification.Name("IslandShowSetup")
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
