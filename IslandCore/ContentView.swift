//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var vm: IslandViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = IslandCoordinator.shared
    @ObservedObject var canvas = IslandCanvasStore.shared
    @ObservedObject var appearance=IslandAppearanceStore.shared
    @ObservedObject var snooze=IslandSnooze.shared
    @ObservedObject var activityClock=IslandLiveActivityClock.shared
    @ObservedObject var liveAgenda=IslandAgenda.shared
    @ObservedObject var calendars=IslandCalendarStore.shared
    @ObservedObject var liveDevices=IslandDevices.shared
    @ObservedObject var liveNotices=IslandNotices.shared
    @ObservedObject var focusTimer = IslandFocusTimer.shared
    @ObservedObject var agentBridge = IslandAgentBridge.shared
    @ObservedObject var activityTrays=IslandActivityTrayStore.shared
    @ObservedObject var moduleStore=IslandModuleStore.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var hoveredActivity:IslandCompactKind?
    @State private var manualActivity:IslandCompactKind?
    @State private var dismissedActivities:[IslandCompactKind:String]=[:]
    @State private var handledUpGesture=false
    @State private var handledDownGesture=false
    @AppStorage("island.live.duo") private var duo=false
    @AppStorage("island.live.idle") private var idleActivity="none"
    @AppStorage("island.gesture.middleCycle") private var middleCycle=true
    @AppStorage("island.gesture.skip") private var swipeSkip=true
    @AppStorage("island.gesture.dismiss") private var swipeDismiss=true
    @AppStorage("island.gesture.downCycle") private var downCycle=true
    @AppStorage("island.live.hidePaused") private var hidePaused=false
    @AppStorage("island.live.musicQuickControls") private var musicQuickControls=true
    @AppStorage("island.live.aiPriority") private var aiPriority=true
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private var surfaceAnimation: Animation {
        reduceMotion ? .easeOut(duration:0.12) : .spring(response:0.36,dampingFraction:appearance.preferences.elasticSurface == true ? 0.86 : 1,blendDuration:0)
    }

    private var contentTransition:AnyTransition {
        guard !reduceMotion,appearance.preferences.progressiveBlur == true else { return .opacity }
        return .modifier(active:IslandContentReveal(radius:6,opacity:0),identity:IslandContentReveal(radius:0,opacity:1))
    }
    private var compactKind: IslandCompactKind {
        if coordinator.sneakPeek.show && [.volume,.brightness,.backlight,.mic].contains(coordinator.sneakPeek.type) && (coordinator.hudDisplayID==nil || NSScreen.screen(withUUID:vm.screenUUID ?? "")?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == coordinator.hudDisplayID.map { NSNumber(value:$0) }) { return .hud }
        if coordinator.expandingView.show && coordinator.expandingView.type == .battery && Defaults[.showPowerStatusNotifications] { return .battery }
        let available=availableCompactKinds
        if !agentBridge.pending.isEmpty && available.contains(.agent) { return .agent }
        if let manualActivity,available.contains(manualActivity) { return manualActivity }
        if available.contains(.agent),IslandActivityRules.prioritizeAgent(enabled:activityTrays.preferences.enabled.contains(.agent),moduleEnabled:moduleStore.enabled.contains(.agents),pending:false,working:agentBridge.activePluginProgress != nil,preferWork:aiPriority,hovering:isHovering) { return .agent }
        if available.isEmpty {
            if idleActivity == "calendar" && (moduleStore.enabled.contains(.calendar) || moduleStore.enabled.contains(.day)) { return .event }
            if idleActivity == "wellbeing" && moduleStore.enabled.contains(.health) { return .wellbeing }
        }
        return IslandActivityRules.choose(available,rotate:UserDefaults.standard.bool(forKey:"island.live.rotate"),phase:activityClock.phase,hovered:isHovering ? hoveredActivity : nil)
    }
    private var availableCompactKinds:[IslandCompactKind] {

        let defaults=UserDefaults.standard,modules=moduleStore.enabled
        let timerActive=(focusTimer.state.deadline != nil || focusTimer.showCompletion) && modules.contains(.focus) && activityTrays.preferences.enabled.contains(.timer)
        var available:[IslandCompactKind]=[]
        if timerActive { available.append(.timer) }
        if !musicManager.isPlayerIdle && (!hidePaused || musicManager.isPlaying) && coordinator.musicLiveActivityEnabled && modules.contains(.home) && !IslandActivityRules.excluded(musicManager.bundleIdentifier,from:defaults.string(forKey:"island.live.excludedPlayers") ?? "") { available.append(.music) }
        if activityTrays.preferences.enabled.contains(.event),(modules.contains(.calendar) || modules.contains(.day)),!calendars.activity(liveAgenda.events).isEmpty { available.append(.event) }
        if activityTrays.preferences.enabled.contains(.device),modules.contains(.devices),!liveDevices.devices.isEmpty { available.append(.device) }
        if activityTrays.preferences.enabled.contains(.notice),modules.contains(.inbox),liveNotices.items.contains(where:{ !$0.read }) { available.append(.notice) }
        if modules.contains(.health) { available.append(.wellbeing) }
        if modules.contains(.agents),agentBridge.activePluginProgress != nil || !agentBridge.pending.isEmpty { available.append(.agent) }
        return activityTrays.preferences.arrange(available).filter { dismissedActivities[$0] != activityToken($0) }
    }
    private func activityToken(_ kind:IslandCompactKind)->String {
        switch kind {
        case .music:return (musicManager.bundleIdentifier ?? "")+musicManager.songTitle+musicManager.album
        case .timer:return String(focusTimer.state.deadline?.timeIntervalSince1970 ?? 0)+String(focusTimer.showCompletion)
        case .event:return calendars.activity(liveAgenda.events).first.map { $0.calendarItemIdentifier+":"+String($0.startDate.timeIntervalSince1970) } ?? "calendar"
        case .device:return liveDevices.devices.map(\.id).joined(separator:",")
        case .notice:return liveNotices.items.filter { !$0.read }.map(\.id).joined(separator:",")
        case .agent:return agentBridge.pending.first?.id ?? agentBridge.activePluginProgress?.id ?? "agent"
        case .wellbeing:return String(UserDefaults.standard.integer(forKey:"island.health.water"))
        default:return kind.rawValue
        }
    }
    private var secondaryCompactKind:IslandCompactKind? { IslandActivityRules.secondary(primary:compactKind,available:availableCompactKinds,enabled:duo) }
    private func cycleActivity() {
        let available=availableCompactKinds
        guard !available.isEmpty else { return }
        let next=available[((available.firstIndex(of:compactKind) ?? -1)+1)%available.count]
        manualActivity=next;hoveredActivity=next
        if vm.notchState == .open { IslandCompactActivity.route(next) }
        IslandHaptics.play(.selection)
    }
    private var topCornerRadius: CGFloat { 0 }
    private var currentNotchShape: IslandSurface {
        let screen=vm.screenUUID.flatMap { NSScreen.screen(withUUID:$0) } ?? NSScreen.main
        let pill=vm.notchState == .closed && (screen?.safeAreaInsets.top ?? 0)==0 && appearance.preferences.notchlessStyle == "pill"
        return IslandSurface(radius:vm.notchState == .open ? 30 : 14,pill:pill)
    }
    private var showsMusicControls:Bool { IslandCompactLayout.showsMusicControls(kind:compactKind,hovering:isHovering,closed:vm.notchState == .closed,enabled:musicQuickControls && secondaryCompactKind == nil) }
    private var computedChinWidth: CGFloat { max(compactKind == .idle ? 60 : 0,IslandCompactLayout.width(camera:vm.compactCameraWidth,kind:compactKind,musicControls:showsMusicControls,secondary:secondaryCompactKind)) }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = ZStack(alignment:.top) {
                    if vm.notchState == .open {
                        // Clip a fixed canvas instead of relaying out controls as the surface shrinks.
                        expandedContent
                            .padding(.horizontal,20)
                            .padding(.bottom,12)
                            .frame(width:openNotchSize.width,height:openNotchSize.height,alignment:.top)
                            .transition(.asymmetric(insertion:contentTransition.animation(.easeOut(duration:0.16)),removal:contentTransition.animation(.easeOut(duration:0.10))))
                    } else {
                        IslandCompactActivity(kind:compactKind,showsMusicControls:showsMusicControls,secondary:secondaryCompactKind)
                            .transition(.opacity.animation(.easeOut(duration:0.12)))
                    }
                }
                    .frame(width:vm.notchState == .open ? openNotchSize.width : computedChinWidth,
                           height:vm.notchState == .open ? openNotchSize.height : vm.effectiveClosedNotchHeight,alignment:.top)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay {
                        if appearance.preferences.outline != "off" && (vm.notchState == .open || appearance.preferences.compactOutline) {
                            currentNotchShape.stroke(appearance.preferences.outline == "color" ? appearance.color.opacity(0.8) : .white.opacity(0.18),lineWidth:1).padding(0.5).allowsHitTesting(false)
                        }
                    }
                    .shadow(color:vm.notchState == .open ? .black.opacity(0.25) : .clear,radius:12,y:6)

                mainLayout
                    .background(IslandActivityInput(middleClick:middleCycle,horizontal:vm.notchState == .closed && swipeSkip && compactKind == .music,onCycle:cycleActivity,onSkip:{ forward in if forward { musicManager.nextTrack() } else { musicManager.previousTrack() };IslandHaptics.play(.selection) }))
                    .opacity(snooze.active ? 0 : 1).allowsHitTesting(!snooze.active)
                    .environment(\.colorScheme, .dark)
                    .animation(surfaceAnimation,value:vm.notchState)
                    .animation(surfaceAnimation,value:computedChinWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onReceive(NotificationCenter.default.publisher(for:Notification.Name("IslandActivityTraysChanged"))) { _ in IslandLiveActivityClock.shared.configure() }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            isHovering = false
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                IslandSettingsController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(animationSpring, value: gestureProgress)
        .background(dragDetector)
        .environment(\.islandSystemColorScheme, systemColorScheme)
        .environmentObject(vm)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if !isHovering && !vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose { vm.close() }
        }
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("IslandCycleActivity"))) { notification in
            if let target=notification.object as? IslandViewModel,target === vm { cycleActivity() }
        }
        .onChange(of:availableCompactKinds) { _,available in if let manualActivity,!available.contains(manualActivity) { self.manualActivity=nil } }
        .onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil); vm.close() }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted && IslandModuleStore.shared.enabled.contains(.shelf) {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    private var expandedContent: some View {
            VStack(spacing:0) {
                IslandHeader().frame(height:34)
                Rectangle().fill(.white.opacity(0.07)).frame(height:1).padding(.top,3)
                Group {
                    if canvas.preferences.showsLayout(currentView:coordinator.currentView,showingDetail:coordinator.showingCanvasDetail) { IslandCanvasLiveView() }
                    else {
                    switch coordinator.currentView {
                    case .home: IslandNowPlayingView()
                    case .shelf: IslandTrayView()
                    case .focus: IslandFocusView()
                    case .notes: IslandNotesView()
                    case .dashboard: IslandDashboardView()
                    default: IslandModuleContent(module:coordinator.currentView)
                    }
                    }
                }.frame(height:150,alignment:.top).padding(.top,12)
            }
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        vm.open()
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if snooze.active { return }
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            hoveredActivity=compactKind
            isHovering = true
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  !showsMusicControls,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.isHovering = false
                    self.hoveredActivity=nil
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended { handledDownGesture=false;withAnimation(animationSpring) { gestureProgress = .zero };return }
        guard !handledDownGesture else { return }
        if vm.notchState == .open {
            if downCycle,translation>Defaults[.gestureSensitivity] { handledDownGesture=true;cycleActivity() }
            return
        }
        if !dismissedActivities.isEmpty && translation>Defaults[.gestureSensitivity] {
            handledDownGesture=true;dismissedActivities=[:];IslandHaptics.play(.selection);return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            handledDownGesture=true
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended { handledUpGesture=false;withAnimation(animationSpring) { gestureProgress = .zero };return }
        guard !handledUpGesture && !vm.isHoveringCalendar else { return }
        if vm.notchState == .closed {
            if swipeDismiss,translation>Defaults[.gestureSensitivity],![IslandCompactKind.idle,.hud,.battery].contains(compactKind) {
                handledUpGesture=true;dismissedActivities[compactKind]=activityToken(compactKind);manualActivity=nil;hoveredActivity=nil;IslandHaptics.play(.selection)
            }
            return
        }
        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            handledUpGesture=true
            isHovering = false
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = IslandViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
