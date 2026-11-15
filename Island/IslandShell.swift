import SwiftUI
import Defaults

// Island's own bounded surface and physical-camera-safe activity layout.
enum IslandCompactKind:String,CaseIterable { case idle, music, timer, hud, battery, agent, event, device, notice, wellbeing }
struct IslandCompactLayout {
    static func wing(for kind:IslandCompactKind,musicControls:Bool=false) -> CGFloat {
        if kind == .music && musicControls { return 64 }
        switch kind { case .idle: return 0; case .music: return 34;case .hud:return 86;case .timer,.battery,.agent,.event,.device,.notice,.wellbeing: return 64 }
    }
    static func width(camera:CGFloat,kind:IslandCompactKind,musicControls:Bool=false,secondary:IslandCompactKind?=nil) -> CGFloat { max(0,camera) + 2 * (secondary == nil ? wing(for:kind,musicControls:musicControls) : 96) }
    static func showsMusicControls(kind:IslandCompactKind,hovering:Bool,closed:Bool,enabled:Bool)->Bool { kind == .music && hovering && closed && enabled }
}
struct IslandSurface: Shape {
    var radius:CGFloat
    var pill=false
    var animatableData:CGFloat { get { radius } set { radius = newValue } }
    func path(in rect:CGRect) -> Path {
        let r = min(radius,min(rect.height,rect.width/2))
        if pill { return RoundedRectangle(cornerRadius:r,style:.continuous).path(in:rect) }
        var path = Path(); path.move(to:CGPoint(x:rect.minX,y:rect.minY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY-r)); path.addQuadCurve(to:CGPoint(x:rect.maxX-r,y:rect.maxY),control:CGPoint(x:rect.maxX,y:rect.maxY)); path.addLine(to:CGPoint(x:rect.minX+r,y:rect.maxY)); path.addQuadCurve(to:CGPoint(x:rect.minX,y:rect.maxY-r),control:CGPoint(x:rect.minX,y:rect.maxY)); path.closeSubpath(); return path
    }
}
struct IslandMark:View {
    var size:CGFloat = 44
    var body:some View {
        ZStack {
            RoundedRectangle(cornerRadius:size*0.25).fill(LinearGradient(colors:[Color(red:0.24,green:0.67,blue:1),Color(red:0.17,green:0.31,blue:0.9)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Capsule().fill(.black).frame(width:size*0.70,height:size*0.29)
            Capsule().fill(.white.opacity(0.8)).frame(width:size*0.15,height:size*0.04).offset(x:-size*0.17,y:-size*0.045)
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}
struct IslandHeader:View {
    @EnvironmentObject var vm:IslandViewModel
    @ObservedObject var battery = BatteryStatusViewModel.shared
    @ObservedObject var canvas=IslandCanvasStore.shared
    @ObservedObject var coordinator=IslandCoordinator.shared
    var body:some View {
        HStack(spacing:0) {
            TabSelectionView().frame(maxWidth:.infinity,alignment:.leading)
            Color.clear.frame(width:min(130,vm.closedNotchSize.width * 0.65)).allowsHitTesting(false)
            HStack(spacing:8) {
                if canvas.preferences.enabled && (coordinator.currentView != .dashboard || coordinator.showingCanvasDetail) {
                    Button { coordinator.showingCanvasDetail=false;coordinator.currentView = .dashboard } label: { Image(systemName:"square.grid.2x2").frame(width:28,height:26) }.help("Back to your layout").accessibilityLabel("Back to your layout")
                }
                Button { vm.isPinned.toggle() } label: { Image(systemName:vm.isPinned ? "pin.fill" : "pin").foregroundStyle(vm.isPinned ? .cyan : .secondary).frame(width:28,height:26) }.help(vm.isPinned ? "Unpin Island" : "Keep Island open").accessibilityLabel(vm.isPinned ? "Unpin Island" : "Pin Island")
                Button { IslandSettingsController.shared.showWindow() } label: { Image(systemName:"slider.horizontal.3").frame(width:28,height:26) }.help("Customize Island").accessibilityLabel("Island settings")
                if Defaults[.showBatteryIndicator] {
                    IslandBatteryButton(batteryWidth:29,isCharging:battery.isCharging,isInLowPowerMode:battery.isInLowPowerMode,isPluggedIn:battery.isPluggedIn,levelBattery:battery.levelBattery,maxCapacity:battery.maxCapacity,timeToFullCharge:battery.timeToFullCharge,isForNotification:false)
                }
            }.font(.system(size:13,weight:.medium)).buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.trailing)
        }.frame(height:34).font(.system(size:13,weight:.medium))
    }
}
struct IslandCompactActivity:View {
    let kind:IslandCompactKind
    var showsMusicControls=false
    var secondary:IslandCompactKind?=nil
    @EnvironmentObject var vm:IslandViewModel
    @ObservedObject var focus = IslandFocusTimer.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var coordinator = IslandCoordinator.shared
    @ObservedObject var battery = BatteryStatusViewModel.shared
    @ObservedObject var bridge = IslandAgentBridge.shared
    @ObservedObject var agenda=IslandAgenda.shared
    @ObservedObject var calendars=IslandCalendarStore.shared
    @ObservedObject var devices=IslandDevices.shared
    @ObservedObject var notices=IslandNotices.shared
    @AppStorage("island.health.water") private var water=0
    @AppStorage("island.health.waterGoal") private var waterGoal=8
    @AppStorage("island.health.day") private var healthDay=""
    var body:some View {
        let wing = IslandCompactLayout.wing(for:kind,musicControls:showsMusicControls)
        Group {
        if kind == .idle { Button(action:openActivity) { Color.black.frame(width:max(60,vm.compactCameraWidth),height:vm.effectiveClosedNotchHeight) }.buttonStyle(.plain).accessibilityLabel("Open Island") } else if kind == .hud { IslandCompactHUD() } else if let secondary { duo(secondary) } else if kind == .music && showsMusicControls {
            HStack(spacing:0) {
                HStack(spacing:2) {
                    Button { music.previousTrack();IslandHaptics.play(.selection) } label:{ Image(systemName:"backward.fill").frame(width:26,height:28) }.accessibilityLabel("Previous track")
                    Button(action:openActivity) { Image(nsImage:music.albumArt).resizable().scaledToFill().frame(width:20,height:20).clipShape(RoundedRectangle(cornerRadius:5)) }.accessibilityLabel("Open Now Playing")
                }.frame(width:wing)
                Button(action:openActivity) { Color.black.frame(width:vm.compactCameraWidth,height:vm.effectiveClosedNotchHeight) }.accessibilityLabel("Open Island")
                HStack(spacing:2) {
                    Button { music.togglePlay();IslandHaptics.play(.confirmation) } label:{ Image(systemName:music.isPlaying ? "pause.fill" : "play.fill").frame(width:26,height:28) }.accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                    Button { music.nextTrack();IslandHaptics.play(.selection) } label:{ Image(systemName:"forward.fill").frame(width:26,height:28) }.accessibilityLabel("Next track")
                }.frame(width:wing)
            }.frame(height:vm.effectiveClosedNotchHeight).buttonStyle(.plain).font(.system(size:11,weight:.semibold)).foregroundStyle(.white)
        } else { Button(action:openActivity) {
            HStack(spacing:0) {
                leading(kind).frame(width:wing)
                Color.black.frame(width:vm.compactCameraWidth).allowsHitTesting(false)
                trailing(kind).frame(width:wing)
            }
            .frame(width:IslandCompactLayout.width(camera:vm.compactCameraWidth,kind:kind),height:vm.effectiveClosedNotchHeight)
            .font(.system(size:11,weight:.semibold,design:.rounded)).lineLimit(1)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(kind == .agent ? "Open AI activity and questions" : kind == .wellbeing ? "Open Wellbeing" : "Open Island activity") }
        }
    }
    private func openActivity() { openActivity(kind) }
    private func duo(_ other:IslandCompactKind)->some View {
        HStack(spacing:0) {
            duoButton(kind)
            Button { openActivity(kind) } label: { Color.black.frame(width:vm.compactCameraWidth,height:vm.effectiveClosedNotchHeight) }.accessibilityLabel("Open Island")
            duoButton(other)
        }.frame(height:vm.effectiveClosedNotchHeight).buttonStyle(.plain).font(.system(size:10,weight:.semibold,design:.rounded)).lineLimit(1)
    }
    private func duoButton(_ activity:IslandCompactKind)->some View {
        Button { openActivity(activity) } label: {
            HStack(spacing:6) { leading(activity).frame(width:20);trailing(activity) }.frame(width:88,height:vm.effectiveClosedNotchHeight).padding(.horizontal,4).contentShape(Rectangle())
        }.accessibilityLabel("Open "+activity.rawValue+" activity")
    }
    private func openActivity(_ kind:IslandCompactKind) {
        if (UserDefaults.standard.object(forKey:"island.gesture.optionActions") as? Bool ?? true),NSEvent.modifierFlags.contains(.option) {
            if kind == .music { music.togglePlay();IslandHaptics.play(.selection) }
            else { NotificationCenter.default.post(name:Notification.Name("IslandCycleActivity"),object:vm) }
            return
        }
        Self.route(kind)
        vm.open()
    }
    @MainActor static func route(_ kind:IslandCompactKind) {
        let coordinator=IslandCoordinator.shared
        if kind == .wellbeing { coordinator.currentView = .health }
        else if kind == .event { coordinator.currentView = IslandModuleStore.shared.enabled.contains(.calendar) ? .calendar : .day }
        else if kind == .device { coordinator.currentView = .devices }
        else if kind == .notice { coordinator.currentView = .inbox }
        else if kind == .timer { coordinator.currentView = .focus }
        else if kind == .agent { coordinator.currentView = .agents }
        else if kind == .music { coordinator.currentView = .home }
        if ![IslandCompactKind.idle,.hud,.battery].contains(kind) { coordinator.showingCanvasDetail=true }
    }
    @ViewBuilder func leading(_ activity:IslandCompactKind)->some View {
        switch activity {
        case .idle: Color.clear
        case .wellbeing:Image(systemName:"drop.fill").foregroundStyle(.cyan)
        case .event:Image(systemName:"calendar").foregroundStyle(.orange)
        case .device:Image(systemName:"headphones").foregroundStyle(.cyan)
        case .notice:Image(systemName:"bell.badge.fill").foregroundStyle(.cyan)
        case .agent: Image(systemName:bridge.pending.isEmpty ? "sparkles" : "questionmark.bubble.fill").foregroundStyle(.cyan)
        case .timer: Image(systemName:focus.showCompletion ? "checkmark.circle.fill" : "timer").foregroundStyle(.orange)
        case .music: Image(nsImage:music.albumArt).resizable().scaledToFill().frame(width:18,height:18).clipShape(RoundedRectangle(cornerRadius:5))
        case .hud: Image(systemName:coordinator.sneakPeek.icon.isEmpty ? "speaker.wave.2.fill" : coordinator.sneakPeek.icon).foregroundStyle(.white)
        case .battery: Image(systemName:battery.isCharging ? "bolt.fill" : "battery.100").foregroundStyle(.green)
        }
    }
    @ViewBuilder func trailing(_ activity:IslandCompactKind)->some View {
        switch activity {
        case .idle: Color.clear
        case .wellbeing:Text("\(healthDay == Date().formatted(.iso8601.year().month().day()) ? max(0,water) : 0)/\(max(1,waterGoal))").monospacedDigit().foregroundStyle(.cyan)
        case .event:
            if let event=calendars.activity(agenda.events).first { Text(event.startDate<=Date() ? "Now" : "\(max(1,Int(event.startDate.timeIntervalSinceNow/60))) min").monospacedDigit().foregroundStyle(.orange) } else { Text(Date(),format:.dateTime.month(.abbreviated).day()).foregroundStyle(.orange) }
        case .device:Text(devices.devices.compactMap(\.battery).min().map { "\($0)%" } ?? "Connected").foregroundStyle(.cyan)
        case .notice:Text("\(notices.items.filter { !$0.read }.count) unread").foregroundStyle(.cyan)
        case .agent: Text(bridge.pending.isEmpty ? (bridge.activePluginProgress?.percent.map { "\(Int($0))%" } ?? "Working") : "\(bridge.pending.count) waiting").foregroundStyle(.cyan)
        case .timer: Text(focus.showCompletion ? "Done" : focus.label).monospacedDigit().foregroundStyle(.orange)
        case .music: IslandLiveWaveform(playing:music.isPlaying)
        case .hud: ProgressView(value:min(1,max(0,Double(coordinator.sneakPeek.value)))).progressViewStyle(.linear).tint(.white).padding(.horizontal,10)
        case .battery: Text("\(islandBatteryPercent(battery.levelBattery))%").monospacedDigit().foregroundStyle(.green)
        }
    }
}
struct IslandNowPlayingView:View {
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var appearance=IslandAppearanceStore.shared
    @State var seek = 0.0
    @State var seeking = false
    @State private var showOutputs=false
    var body:some View {
        HStack(spacing:22) {
            Group {
                if music.isPlayerIdle { RoundedRectangle(cornerRadius:22).fill(.white.opacity(0.055)).overlay { Image(systemName:"music.note").font(.system(size:34)).foregroundStyle(.secondary) } }
                else { Image(nsImage:music.albumArt).resizable().scaledToFill() }
            }.frame(width:112,height:112)
                .background(appearance.preferences.clearArtwork ? .clear : Color.white.opacity(0.05))
                .saturation(appearance.preferences.grayscaleArtwork ? 0 : 1)
                .opacity(music.isPlayerIdle || music.isPlaying ? 1 : appearance.preferences.pausedArtworkOpacity)
                .overlay { if appearance.preferences.artworkGlare && !music.isPlayerIdle { LinearGradient(colors:[.white.opacity(0.22),.clear,.white.opacity(0.05)],startPoint:.topLeading,endPoint:.bottomTrailing).allowsHitTesting(false) } }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius:22))
                .background(IslandActivityInput(middleClick:false,horizontal:!music.isPlayerIdle && (UserDefaults.standard.object(forKey:"island.gesture.skip") as? Bool ?? true),onCycle:{},onSkip:{ forward in if forward { music.nextTrack() } else { music.previousTrack() };IslandHaptics.play(.selection) }))
            VStack(alignment:.leading,spacing:5) {
                if music.isPlayerIdle {
                    Text("Not Playing").font(.system(size:22,weight:.semibold))
                    Text("Your music, right here.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Open Music") { music.openMusicApp() }.buttonStyle(.bordered).padding(.top,5)
                    if Defaults[.mediaController] == .appleMusic || Defaults[.mediaController] == .spotify { Button("Set up player…") { IslandSettingsController.shared.showPermissions(Defaults[.mediaController] == .spotify ? .spotify : .music) }.buttonStyle(.borderless) }
                } else {
                    HStack(alignment:.firstTextBaseline,spacing:6) {
                        Text(appearance.preferences.title(music.songTitle)).font(.system(size:17,weight:.semibold)).lineLimit(1).truncationMode(.tail).frame(maxWidth:.infinity,alignment:.leading)
                        Menu {
                            Button(music.isShuffled ? "Turn Shuffle Off" : "Turn Shuffle On",systemImage:"shuffle") { music.toggleShuffle() }.disabled(!music.shuffleSupported)
                            Button(music.repeatMode == .off ? "Repeat All" : music.repeatMode == .all ? "Repeat One" : "Turn Repeat Off",systemImage:music.repeatMode == .one ? "repeat.1" : "repeat") { music.toggleRepeat() }.disabled(!music.repeatSupported)
                            if music.canFavoriteTrack { Button(music.isFavoriteTrack ? "Remove Favorite" : "Favorite",systemImage:music.isFavoriteTrack ? "star.fill" : "star") { music.toggleFavoriteTrack() } }
                            if music.playbackRateSupported { Menu("Playback Speed") { ForEach([0.5,0.75,1,1.25,1.5,1.75,2,2.5,3],id:\.self) { rate in Button("\(rate.formatted())×") { music.setPlaybackRate(rate) } } } }
                            Divider()
                            if let url=music.trackURL { Button("Copy Track Link",systemImage:"link") { NSPasteboard.general.clearContents();NSPasteboard.general.setString(url.absoluteString,forType:.string) };Button("Show Current Track",systemImage:"arrow.up.right.square") { music.openCurrentTrack() } }
                            Button("Copy Song Details",systemImage:"doc.on.doc") { NSPasteboard.general.clearContents();NSPasteboard.general.setString([music.songTitle,music.artistName,music.album].filter { !$0.isEmpty }.joined(separator:" — "),forType:.string) }
                            Button("Audio Output…",systemImage:"airplay.audio") { showOutputs=true }
                            Button("Open Player",systemImage:"arrow.up.right.square") { music.openMusicApp() }
                        } label:{ Image(systemName:"ellipsis.circle").font(.system(size:17)) }.menuStyle(.borderlessButton).fixedSize().help("Playback options")
                    }
                    HStack(spacing:6) {
                        Text(music.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).frame(maxWidth:.infinity,alignment:.leading)
                        if music.isExplicit==true { Text("E").font(.system(size:8,weight:.bold)).padding(.horizontal,3).padding(.vertical,1).background(.secondary.opacity(0.3),in:RoundedRectangle(cornerRadius:2)).accessibilityLabel("Explicit") }
                        if music.isShuffled { Image(systemName:"shuffle").font(.caption).foregroundStyle(.green) }
                        if music.repeatMode != .off { Image(systemName:music.repeatMode == .one ? "repeat.1" : "repeat").font(.caption).foregroundStyle(.green) }
                        if music.playbackRate != 1,music.playbackRate>0 { Text("\(music.playbackRate.formatted(.number.precision(.fractionLength(0...2))))×").font(.caption).foregroundStyle(.secondary) }
                    }
                    TimelineView(.periodic(from:.now,by:0.5)) { context in
                        let elapsed=music.estimatedPlaybackPosition(at:context.date)
                        let position=Binding(get:{ seeking ? seek : min(max(0,elapsed),max(1,music.songDuration)) },set:{ seek = $0 })
                        let editing:(Bool)->Void = { editing in seeking=editing;if !editing { music.seek(to:seek);IslandHaptics.play(.placement) } }
                        VStack(spacing:0) {
                            Group {
                                if appearance.preferences.gradientProgress { IslandGradientSlider(value:position,upperBound:max(1,music.songDuration),onEditingChanged:editing) }
                                else { Slider(value:position,in:0...max(1,music.songDuration),onEditingChanged:editing).tint(.white) }
                            }.disabled(music.songDuration <= 0).accessibilityLabel("Playback position")
                            HStack { Text(IslandMediaRules.time(seeking ? seek : elapsed));Spacer();if music.songDuration>0 { Text(IslandMediaRules.time(music.songDuration)) } }.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing:20) {
                        Button { IslandHaptics.play(.selection);if music.supportsBackward15 { music.skip(seconds:-15) } else { music.previousTrack() } } label: { Image(systemName:music.supportsBackward15 ? "gobackward.15" : "backward.fill") }.frame(width:28,height:28).accessibilityLabel(music.supportsBackward15 ? "Back 15 seconds" : "Previous track").disabled(music.prohibitsSkip)
                        Button { IslandHaptics.play(.confirmation);music.togglePlay() } label: { Image(systemName:music.isPlaying ? "pause.fill" : "play.fill").font(.system(size:23)) }.frame(width:34,height:28).accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                        Button { IslandHaptics.play(.selection);if music.supportsForward15 { music.skip(seconds:15) } else { music.nextTrack() } } label: { Image(systemName:music.supportsForward15 ? "goforward.15" : "forward.fill") }.frame(width:28,height:28).accessibilityLabel(music.supportsForward15 ? "Forward 15 seconds" : "Next track").disabled(music.prohibitsSkip)
                        Spacer()
                        if music.volumeControlSupported { Slider(value:Binding(get:{ music.volume },set:{ music.setVolume(to:$0) }),in:0...1).frame(width:70).tint(.white).accessibilityLabel("Player volume") }
                        Button { music.openMusicApp() } label: { Image(systemName:"arrow.up.right.square") }.frame(width:28,height:28).help("Open player")
                    }.buttonStyle(.plain).font(.system(size:15))
                }
            }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        }.frame(height:134).padding(.horizontal,12)
        .onChange(of:music.songTitle) { seeking = false; seek = music.elapsedTime }
        .popover(isPresented:$showOutputs) { IslandAudioOutputView().frame(width:320).padding(16) }
    }
}
