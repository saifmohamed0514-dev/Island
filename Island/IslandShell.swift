import SwiftUI
import Defaults

// Island's own bounded surface and physical-camera-safe activity layout.
enum IslandCompactKind { case idle, music, timer, hud, battery, agent, event, device, notice }
struct IslandCompactLayout {
    static func wing(for kind:IslandCompactKind) -> CGFloat {
        switch kind { case .idle: return 0; case .music: return 34; case .timer,.hud,.battery,.agent,.event,.device,.notice: return 64 }
    }
    static func width(camera:CGFloat,kind:IslandCompactKind) -> CGFloat { max(0,camera) + 2 * wing(for:kind) }
}
struct IslandSurface: Shape {
    var radius:CGFloat
    var animatableData:CGFloat { get { radius } set { radius = newValue } }
    func path(in rect:CGRect) -> Path {
        let r = min(radius,min(rect.height,rect.width/2))
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
                    Button { coordinator.showingCanvasDetail=false;coordinator.currentView = .dashboard } label: { Image(systemName:"square.grid.2x2") }.help("Back to your layout").accessibilityLabel("Back to your layout")
                }
                Button { vm.isPinned.toggle() } label: { Image(systemName:vm.isPinned ? "pin.fill" : "pin").foregroundStyle(vm.isPinned ? .cyan : .secondary) }.help(vm.isPinned ? "Unpin Island" : "Keep Island open").accessibilityLabel(vm.isPinned ? "Unpin Island" : "Pin Island")
                Button { IslandSettingsController.shared.showWindow() } label: { Image(systemName:"slider.horizontal.3") }.help("Customize Island").accessibilityLabel("Island settings")
                if Defaults[.showBatteryIndicator] {
                    IslandBatteryButton(batteryWidth:29,isCharging:battery.isCharging,isInLowPowerMode:battery.isInLowPowerMode,isPluggedIn:battery.isPluggedIn,levelBattery:battery.levelBattery,maxCapacity:battery.maxCapacity,timeToFullCharge:battery.timeToFullCharge,isForNotification:false)
                }
            }.font(.system(size:13,weight:.medium)).buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.trailing)
        }.frame(height:34)
    }
}
struct IslandCompactActivity:View {
    let kind:IslandCompactKind
    @EnvironmentObject var vm:IslandViewModel
    @ObservedObject var focus = IslandFocusTimer.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var coordinator = IslandCoordinator.shared
    @ObservedObject var battery = BatteryStatusViewModel.shared
    @ObservedObject var bridge = IslandAgentBridge.shared
    @ObservedObject var agenda=IslandAgenda.shared
    @ObservedObject var devices=IslandDevices.shared
    @ObservedObject var notices=IslandNotices.shared
    var body:some View {
        let wing = IslandCompactLayout.wing(for:kind)
        HStack(spacing:0) {
            leading.frame(width:wing)
            Color.black.frame(width:vm.closedNotchSize.width).allowsHitTesting(false)
            trailing.frame(width:wing)
        }
        .frame(width:IslandCompactLayout.width(camera:vm.closedNotchSize.width,kind:kind),height:vm.effectiveClosedNotchHeight)
        .font(.system(size:11,weight:.semibold,design:.rounded)).lineLimit(1)
        .contentShape(Rectangle())
        .onTapGesture {
            if kind == .event { coordinator.currentView = IslandModuleStore.shared.enabled.contains(.calendar) ? .calendar : .day }
            else if kind == .device { coordinator.currentView = .devices }
            else if kind == .notice { coordinator.currentView = .inbox }
            else if kind == .timer { coordinator.currentView = .focus }
            else if kind == .agent { coordinator.currentView = .agents }
            else if kind == .music { coordinator.currentView = .home }
            vm.open()
        }
    }
    @ViewBuilder var leading:some View {
        switch kind {
        case .idle: Color.clear
        case .event:Image(systemName:"calendar").foregroundStyle(.orange)
        case .device:Image(systemName:"headphones").foregroundStyle(.cyan)
        case .notice:Image(systemName:"bell.badge.fill").foregroundStyle(.cyan)
        case .agent: Image(systemName:"hand.raised.fill").foregroundStyle(.cyan)
        case .timer: Image(systemName:focus.showCompletion ? "checkmark.circle.fill" : "timer").foregroundStyle(.orange)
        case .music: Image(nsImage:music.albumArt).resizable().scaledToFill().frame(width:18,height:18).clipShape(RoundedRectangle(cornerRadius:5))
        case .hud: Image(systemName:coordinator.sneakPeek.icon.isEmpty ? "speaker.wave.2.fill" : coordinator.sneakPeek.icon).foregroundStyle(.white)
        case .battery: Image(systemName:battery.isCharging ? "bolt.fill" : "battery.100").foregroundStyle(.green)
        }
    }
    @ViewBuilder var trailing:some View {
        switch kind {
        case .idle: Color.clear
        case .event:
            if let event=agenda.events.first(where:{ $0.endDate>Date() && $0.startDate.timeIntervalSinceNow<1800 }) { Text(event.startDate<=Date() ? "Now" : "\(max(1,Int(event.startDate.timeIntervalSinceNow/60))) min").monospacedDigit().foregroundStyle(.orange) }
        case .device:Text(devices.devices.compactMap(\.battery).min().map { "\($0)%" } ?? "Connected").foregroundStyle(.cyan)
        case .notice:Text("\(notices.items.filter { !$0.read }.count) unread").foregroundStyle(.cyan)
        case .agent: Text("\(bridge.pending.count) waiting").foregroundStyle(.cyan)
        case .timer: Text(focus.showCompletion ? "Done" : focus.label).monospacedDigit().foregroundStyle(.orange)
        case .music: Image(systemName:music.isPlaying ? "waveform" : "pause.fill").foregroundStyle(.cyan)
        case .hud: ProgressView(value:min(1,max(0,Double(coordinator.sneakPeek.value)))).progressViewStyle(.linear).tint(.white).padding(.horizontal,10)
        case .battery: Text("\(islandBatteryPercent(battery.levelBattery))%").monospacedDigit().foregroundStyle(.green)
        }
    }
}
struct IslandNowPlayingView:View {
    @ObservedObject var music = MusicManager.shared
    @State var seek = 0.0
    @State var seeking = false
    var body:some View {
        HStack(spacing:22) {
            Group {
                if music.isPlayerIdle { RoundedRectangle(cornerRadius:22).fill(.white.opacity(0.055)).overlay { Image(systemName:"music.note").font(.system(size:34)).foregroundStyle(.secondary) } }
                else { Image(nsImage:music.albumArt).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius:22)) }
            }.frame(width:112,height:112)
            VStack(alignment:.leading,spacing:8) {
                if music.isPlayerIdle {
                    Text("Not Playing").font(.system(size:22,weight:.semibold))
                    Text("Your music, right here.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Open Music") { music.openMusicApp() }.buttonStyle(.bordered).padding(.top,5)
                    if Defaults[.mediaController] == .appleMusic || Defaults[.mediaController] == .spotify { Button("Set up player…") { IslandSettingsController.shared.showPermissions(Defaults[.mediaController] == .spotify ? .spotify : .music) }.buttonStyle(.borderless) }
                } else {
                    Text(music.songTitle).font(.system(size:17,weight:.semibold)).lineLimit(1)
                    Text(music.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    TimelineView(.periodic(from:.now,by:0.5)) { context in
                        Slider(value:Binding(get:{ seeking ? seek : min(max(0,music.estimatedPlaybackPosition(at:context.date)),max(1,music.songDuration)) },set:{ seek = $0 }),in:0...max(1,music.songDuration),onEditingChanged:{ editing in seeking = editing; if !editing { music.seek(to:seek);IslandHaptics.play(.placement) } }).tint(.white).disabled(music.songDuration <= 0).accessibilityLabel("Playback position")
                    }
                    HStack(spacing:25) {
                        Button { IslandHaptics.play(.selection);music.previousTrack() } label: { Image(systemName:"backward.fill") }.accessibilityLabel("Previous track")
                        Button { IslandHaptics.play(.confirmation);music.togglePlay() } label: { Image(systemName:music.isPlaying ? "pause.fill" : "play.fill").font(.system(size:23)) }.accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                        Button { IslandHaptics.play(.selection);music.nextTrack() } label: { Image(systemName:"forward.fill") }.accessibilityLabel("Next track")
                        Spacer()
                        if music.volumeControlSupported { Slider(value:Binding(get:{ music.volume },set:{ music.setVolume(to:$0) }),in:0...1).frame(width:70).tint(.white).accessibilityLabel("Player volume") }
                        Button { music.openMusicApp() } label: { Image(systemName:"arrow.up.right.square") }.help("Open player")
                    }.buttonStyle(.plain).font(.system(size:15))
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.frame(height:134).padding(.horizontal,12)
        .onChange(of:music.songTitle) { seeking = false; seek = music.elapsedTime }
    }
}
