import SwiftUI
import AppKit
import Defaults

enum IslandHUDRules {
    static func label(value:Double,relativeDB:Bool)->String {
        let level=value.isFinite ? min(1,max(0,value)) : 0
        if relativeDB { return level==0 ? "Muted" : "\(Int((20*log10(max(0.001,level))).rounded())) dB" }
        return "\(Int((level*100).rounded()))%"
    }
    static func duration(_ value:Double)->Double { value.isFinite ? min(8,max(0.6,value)) : 1.5 }
}
@MainActor enum IslandHUDMotion {
    static var animation:Animation {
        let defaults=UserDefaults.standard
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .easeOut(duration:0.08) }
        switch defaults.string(forKey:"island.hud.motion") ?? "smooth" {
        case "instant":return .linear(duration:0)
        case "fast":return .easeOut(duration:0.08)
        default:return defaults.bool(forKey:"island.hud.elastic") ? .spring(response:0.25,dampingFraction:0.7) : .smooth(duration:0.18)
        }
    }
}
struct IslandHUDSettings:View {
    @Default(.hudReplacement) private var replacement
    @Default(.enableGradient) private var gradient
    @Default(.systemEventIndicatorUseAccent) private var accent
    @Default(.systemEventIndicatorShadow) private var glow
    @Default(.showClosedNotchHUDPercentage) private var compactPercentage
    @Default(.showOpenNotchHUDPercentage) private var openPercentage
    @AppStorage("island.hud.labels") private var labels=true
    @AppStorage("island.hud.relativeDB") private var relativeDB=false
    @AppStorage("island.hud.motion") private var motion="smooth"
    @AppStorage("island.hud.elastic") private var elastic=false
    @AppStorage("island.hud.duration") private var duration=1.5
    var body:some View {
        Form {
            Section("System indicators") {
                Toggle("Replace system volume and brightness indicators",isOn:$replacement)
                Button("Set up Window and media controls…") { IslandSettingsController.shared.showPermissions(.accessibility) }
                Text("Use the media keys, or drag the slider in Island. The sound icon mutes and restores volume.").font(.caption).foregroundStyle(.secondary)
            }
            IslandBetterDisplaySettings()
            Section("Finishing touches") {
                Toggle("Text labels beside icons",isOn:$labels)
                Toggle("Values while closed",isOn:$compactPercentage)
                Toggle("Values while open",isOn:$openPercentage)
                Toggle("Use the system accent",isOn:$accent)
                Toggle("Gradient fill",isOn:$gradient)
                Toggle("Soft glow",isOn:$glow)
                Toggle("Show volume as relative decibels",isOn:$relativeDB)
                if relativeDB { Text("Relative digital gain, not a measurement of speaker loudness or hearing exposure.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Motion and timing") {
                Picker("Response",selection:$motion) { Text("Smooth").tag("smooth");Text("Fast").tag("fast");Text("Instant").tag("instant") }
                Toggle("Elastic motion",isOn:$elastic).disabled(motion != "smooth")
                Slider(value:$duration,in:0.6...8,step:0.1) { Text("Visible duration") }
                Text("\(IslandHUDRules.duration(duration),specifier:"%.1f") seconds").monospacedDigit().foregroundStyle(.secondary)
                Text("Reduce Motion takes priority over elastic animation.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("Preview current sound level") { IslandCoordinator.shared.toggleSneakPeek(status:true,type:.volume,value:CGFloat(VolumeManager.shared.rawVolume)) }.disabled(!replacement) }
        }.formStyle(.grouped)
    }
}
struct IslandCompactHUD:View {
    @EnvironmentObject private var vm:IslandViewModel
    @ObservedObject private var coordinator=IslandCoordinator.shared
    @AppStorage("island.hud.labels") private var labels=true
    @AppStorage("island.hud.relativeDB") private var relativeDB=false
    @AppStorage("showClosedNotchHUDPercentage") private var percentage=false
    @AppStorage("enableGradient") private var gradient=false
    @AppStorage("systemEventIndicatorUseAccent") private var accent=false
    @AppStorage("systemEventIndicatorShadow") private var glow=false
    private var type:SneakContentType { coordinator.sneakPeek.type }
    private var name:String { switch type { case .volume:return "Sound";case .brightness:return "Display";case .backlight:return "Keys";case .mic:return "Mic";default:return "Control" } }
    private var symbol:String {
        if type == .volume { return coordinator.sneakPeek.value==0 ? "speaker.slash.fill" : coordinator.sneakPeek.icon.isEmpty ? "speaker.wave.2.fill" : coordinator.sneakPeek.icon }
        if type == .brightness { return "display" }
        if type == .backlight { return "light.max" }
        return coordinator.sneakPeek.value>0 ? "mic.fill" : "mic.slash.fill"
    }
    private var value:Binding<Double> { Binding(get:{ min(1,max(0,Double(coordinator.sneakPeek.value))) },set:setValue) }
    var body:some View {
        HStack(spacing:0) {
            Group {
                if type == .volume { Button { if let display=coordinator.hudDisplayID,IslandBetterDisplay.shared.enabled { Task { await IslandBetterDisplay.shared.toggleMute(display:display) } } else { VolumeManager.shared.toggleMuteAction() } } label: { iconAndLabel }.accessibilityLabel("Mute or restore sound").disabled(coordinator.hudControlLocked) }
                else { iconAndLabel }
            }.frame(width:86)
            Color.black.frame(width:vm.compactCameraWidth)
            meter.frame(width:76).padding(.horizontal,5)
        }.frame(height:vm.effectiveClosedNotchHeight).buttonStyle(.plain).foregroundStyle(.white)
    }
    private var iconAndLabel:some View { HStack(spacing:6) { Image(systemName:symbol).font(.system(size:12));if labels { Text(name).font(.system(size:10,weight:.semibold)) } } }
    @ViewBuilder private var meter:some View {
        if type == .mic { Text(coordinator.sneakPeek.value>0 ? "Unmuted" : "Muted").font(.system(size:10,weight:.medium)) }
        else {
            VStack(spacing:1) {
                Group {
                    if gradient { IslandGradientSlider(value:value,upperBound:1,onEditingChanged:{ _ in },colors:accent ? [.blue,.cyan] : [.white,.gray]) }
                    else { Slider(value:value,in:0...1).controlSize(.mini).tint(accent ? .accentColor : .white) }
                }.shadow(color:glow ? (accent ? Color.accentColor : .white).opacity(0.4) : .clear,radius:4)
                if percentage { Text(IslandHUDRules.label(value:value.wrappedValue,relativeDB:relativeDB && type == .volume)).font(.system(size:8,weight:.medium)).monospacedDigit() }
            }.accessibilityLabel(name+" level").disabled(coordinator.hudControlLocked)
        }
    }
    private func setValue(_ level:Double) {
        guard level.isFinite else { return }
        guard !coordinator.hudControlLocked else { return }
        let old=coordinator.sneakPeek.value
        let level=min(1,max(0,level));coordinator.sneakPeek.value=CGFloat(level)
        if let display=coordinator.hudDisplayID,IslandBetterDisplay.shared.enabled,[SneakContentType.volume,.brightness].contains(type) {
            Task { if let actual=await IslandBetterDisplay.shared.set(display:display,feature:type == .volume ? "volume" : "brightness",value:level) { coordinator.sneakPeek.value=CGFloat(actual) } else { coordinator.sneakPeek.value=old } };return
        }
        switch type {
        case .volume:VolumeManager.shared.setAbsolute(Float(level))
        case .brightness:BrightnessManager.shared.setAbsolute(value:Float(level))
        case .backlight:KeyboardBacklightManager.shared.setAbsolute(value:Float(level))
        default:break
        }
    }
}
