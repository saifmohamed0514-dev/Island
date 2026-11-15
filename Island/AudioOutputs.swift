import SwiftUI
import CoreAudio
import AppKit

struct IslandAudioOutput:Identifiable,Equatable { let id:AudioDeviceID;let name:String }
@MainActor final class IslandAudioOutputs:ObservableObject {
    static let shared=IslandAudioOutputs()
    @Published private(set) var devices:[IslandAudioOutput]=[]
    @Published private(set) var selected:AudioDeviceID=0
    @Published private(set) var message:String?
    private var listeners:[(AudioObjectPropertyAddress,AudioObjectPropertyListenerBlock)]=[]
    init() {
        for key in [kAudioHardwarePropertyDevices,kAudioHardwarePropertyDefaultOutputDevice] {
            var address=AudioObjectPropertyAddress(mSelector:key,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            let block:AudioObjectPropertyListenerBlock = { [weak self] _,_ in Task { @MainActor in self?.refresh() } }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,.main,block)==noErr { listeners.append((address,block)) }
        }
        refresh()
    }
    deinit { for (var address,block) in listeners { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,.main,block) } }
    func refresh() {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var current:AudioDeviceID=0,size=UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&current)==noErr { selected=current }
        address.mSelector=kAudioHardwarePropertyDevices;size=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size)==noErr else { devices=[];return }
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&ids)==noErr else { return }
        devices=ids.compactMap { id in
            var streams=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeOutput,mElement:kAudioObjectPropertyElementMain),length:UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&length)==noErr,length>0 else { return nil }
            var nameAddress=AudioObjectPropertyAddress(mSelector:kAudioObjectPropertyName,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain),name:CFString="Audio output" as CFString,nameSize=UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id,&nameAddress,0,nil,&nameSize,&name)==noErr else { return nil }
            return IslandAudioOutput(id:id,name:name as String)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func choose(_ device:IslandAudioOutput) {
        guard devices.contains(device) else { return }
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain),id=device.id
        let status=AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,UInt32(MemoryLayout<AudioDeviceID>.size),&id)
        refresh();message=status==noErr && selected==id ? nil : "macOS couldn’t switch to that output. Check Sound settings and try again."
    }
}
struct IslandAudioOutputView:View {
    @ObservedObject private var outputs=IslandAudioOutputs.shared
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Audio Output").font(.headline)
            Text("Choose where your Mac plays sound.").font(.caption).foregroundStyle(.secondary)
            if outputs.devices.isEmpty { Text("No output devices available.").foregroundStyle(.secondary) }
            ForEach(outputs.devices) { device in
                Button { outputs.choose(device) } label:{ HStack { Image(systemName:"speaker.wave.2");Text(device.name).lineLimit(2);Spacer();if outputs.selected==device.id { Image(systemName:"checkmark").foregroundStyle(.blue) } }.frame(maxWidth:.infinity,alignment:.leading).padding(6) }.buttonStyle(.plain).accessibilityAddTraits(outputs.selected==device.id ? .isSelected : [])
            }
            if let message=outputs.message { Text(message).font(.caption).foregroundStyle(.orange) }
            Divider()
            Button("Sound Settings & AirPlay…") { if let url=URL(string:"x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) } }
            Text("AirPlay and HomePod availability is managed by macOS and the playing app.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { outputs.refresh() }
    }
}
