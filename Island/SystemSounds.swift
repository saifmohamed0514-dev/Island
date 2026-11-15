import SwiftUI
import AppKit
import Intents
import Combine

enum IslandSystemSoundEvent:String,CaseIterable,Identifiable {
    case charging,lowBattery,deviceConnected,deviceDisconnected,deviceLowBattery,focus,lock,unlock
    var id:String { rawValue }
    var title:String { switch self { case .charging:return "Power connected";case .lowBattery:return "Mac battery low";case .deviceConnected:return "Device connected";case .deviceDisconnected:return "Device disconnected";case .deviceLowBattery:return "Device battery low";case .focus:return "Shared Focus changed";case .lock:return "Mac locked";case .unlock:return "Mac unlocked" } }
}
enum IslandSystemSoundRules {
    static let tones=["None","Tink","Pop","Ping","Glass","Purr","Submarine","Blow","Bottle","Frog","Funk","Hero","Morse","Sosumi"]
    static func tone(_ raw:String?)->String { tones.contains(raw ?? "") ? raw! : "None" }
    static func shouldPlay(tone:String,focused:Bool?,quietFocus:Bool,locked:Bool,event:IslandSystemSoundEvent)->Bool { tone != "None" && tones.contains(tone) && !(quietFocus && focused==true) && (!locked || event == .lock || event == .unlock) }
}
@MainActor final class IslandSystemSounds:ObservableObject {
    static let shared=IslandSystemSounds()
    @Published private(set) var message:String?
    @Published private(set) var sharedFocus:Bool?
    private var cancellables=Set<AnyCancellable>()
    private var lastBattery:Int?,wasPlugged:Bool?,lastFocus:Bool?,locked=false
    private var lastPlayed:[IslandSystemSoundEvent:Date]=[:]
    private var player:NSSound?
    private var focusTask:Task<Void,Never>?
    func start() {
        guard cancellables.isEmpty else { return }
        let battery=BatteryStatusViewModel.shared
        battery.$levelBattery.receive(on:DispatchQueue.main).sink { [weak self] raw in
            guard let self else { return };let level=islandBatteryPercent(raw),threshold=20
            defer { self.lastBattery=level }
            if let before=self.lastBattery,before>threshold,level<=threshold,!battery.isPluggedIn { self.play(.lowBattery) }
        }.store(in:&cancellables)
        battery.$isPluggedIn.receive(on:DispatchQueue.main).sink { [weak self] value in
            guard let self else { return };defer { self.wasPlugged=value };if self.wasPlugged==false,value { self.play(.charging) }
        }.store(in:&cancellables)
        focusTask=Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self {
                    let current=INFocusStatusCenter.default.authorizationStatus == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil
                    self.sharedFocus=current
                    if let current { if let last=self.lastFocus,last != current { self.play(.focus) };self.lastFocus=current } else { self.lastFocus=nil }
                }
                do { try await Task.sleep(for:.seconds(10)) } catch { return }
            }
        }
    }
    func setLocked(_ value:Bool) { locked=value;play(value ? .lock : .unlock) }
    func configured(_ event:IslandSystemSoundEvent)->Bool { IslandSystemSoundRules.tone(UserDefaults.standard.string(forKey:"island.sound."+event.rawValue)) != "None" }
    func play(_ event:IslandSystemSoundEvent,preview:Bool=false) {
        let defaults=UserDefaults.standard,tone=IslandSystemSoundRules.tone(defaults.string(forKey:"island.sound."+event.rawValue))
        let focused=INFocusStatusCenter.default.authorizationStatus == .authorized ? INFocusStatusCenter.default.focusStatus.isFocused : nil
        guard preview || IslandSystemSoundRules.shouldPlay(tone:tone,focused:focused,quietFocus:defaults.object(forKey:"island.sound.quietFocus") as? Bool ?? true,locked:locked,event:event) else { return }
        guard tone != "None" else { return }
        if !preview,let last=lastPlayed[event],Date().timeIntervalSince(last)<2 { return }
        player?.stop()
        guard let sound=NSSound(named:NSSound.Name(tone)) else { message="That system sound isn’t available on this Mac. Choose another sound.";return }
        let raw=defaults.object(forKey:"island.sound.volume") as? Double ?? 0.45
        sound.volume=Float(raw.isFinite ? min(1,max(0,raw)) : 0.45)
        guard sound.play() else { message="The sound couldn’t play. Check your audio output.";return }
        player=sound;message=nil;lastPlayed[event]=Date()
    }
}
struct IslandSystemSoundsSettings:View {
    @ObservedObject private var sounds=IslandSystemSounds.shared
    @AppStorage("island.sound.volume") private var volume=0.45
    @AppStorage("island.sound.quietFocus") private var quietFocus=true
    var body:some View {
        Form {
            Section("A little feedback") {
                Text("Optional sounds for power, accessories, shared Focus and locking. All start silent; your focus-timer ringtone stays separate.").foregroundStyle(.secondary)
                Toggle("Quiet while a shared Focus is on",isOn:$quietFocus)
                Slider(value:$volume,in:0...1) { Text("Sound volume") }
                Text("Focus quieting uses the status you chose to share with Island. If a mode doesn’t share a status, Island can’t identify it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("System events") { ForEach(IslandSystemSoundEvent.allCases) { event in IslandSystemSoundRow(event:event) } }
            if let message=sounds.message { Section { Text(message).foregroundStyle(.secondary) } }
            Section { Button("Timer ringtones & presets…") { IslandSettingsNavigation.shared.selected="Focus & Sounds" };Text("Device events require Bluetooth access and the Devices module. Battery estimates and accessory details appear only when macOS reports them.").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}
private struct IslandSystemSoundRow:View {
    let event:IslandSystemSoundEvent
    @State private var tone="None"
    var body:some View { HStack { Picker(event.title,selection:$tone) { ForEach(IslandSystemSoundRules.tones,id:\.self) { Text($0).tag($0) } };Button("Preview") { IslandSystemSounds.shared.play(event,preview:true) }.disabled(tone=="None") }.onAppear { tone=IslandSystemSoundRules.tone(UserDefaults.standard.string(forKey:"island.sound."+event.rawValue)) }.onChange(of:tone) { UserDefaults.standard.set(tone,forKey:"island.sound."+event.rawValue) } }
}
