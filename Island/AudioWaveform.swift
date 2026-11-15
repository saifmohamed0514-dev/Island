import SwiftUI
import CoreAudio
import AudioToolbox
import QuartzCore

// RMS amplitude, never a claimed loudness/quality measurement. Audio never leaves memory.
enum IslandWaveformRules {
    static func amplitude(_ squares:Double,count:Int)->Double {
        guard count>0,squares.isFinite,squares>=0 else { return 0 }
        return min(1,max(0,sqrt(squares/Double(count))*4))
    }
    static func smooth(_ previous:[Double],incoming:[Double])->[Double] {
        (0..<4).map { index in
            let sample=index<incoming.count && incoming[index].isFinite ? min(1,max(0,incoming[index])) : 0
            let old=index<previous.count && previous[index].isFinite ? min(1,max(0,previous[index])) : 0
            return old+(sample-old)*(sample>old ? 0.65 : 0.3)
        }
    }
}
private final class IslandAudioTap {
    private var tap:AudioObjectID=0,device:AudioObjectID=0
    private var proc:AudioDeviceIOProcID?
    private let queue=DispatchQueue(label:"org.islandapp.waveform",qos:.userInitiated)
    private var lastSample=0.0
    deinit { stop() }
    func start(receive:@escaping([Double])->Void) throws {
        stop()
        let description=CATapDescription(stereoGlobalTapButExcludeProcesses:[])
        description.name="Island live waveform";description.uuid=UUID();description.isPrivate=true;description.muteBehavior = .unmuted
        try require(AudioHardwareCreateProcessTap(description,&tap))
        do {
            var format=AudioStreamBasicDescription(),size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address=AudioObjectPropertyAddress(mSelector:kAudioTapPropertyFormat,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            try require(AudioObjectGetPropertyData(tap,&address,0,nil,&size,&format))
            guard format.mFormatID==kAudioFormatLinearPCM,format.mFormatFlags & kAudioFormatFlagIsFloat != 0,format.mBitsPerChannel==32 else { throw NSError(domain:"IslandAudio",code:-1,userInfo:[NSLocalizedDescriptionKey:"This audio format isn’t supported by the waveform."]) }
            let spec:[String:Any]=[kAudioAggregateDeviceNameKey:"Island private waveform",kAudioAggregateDeviceUIDKey:"org.islandapp.waveform."+UUID().uuidString,kAudioAggregateDeviceIsPrivateKey:true,kAudioAggregateDeviceTapAutoStartKey:true,kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:description.uuid.uuidString,kAudioSubTapDriftCompensationKey:true]]]
            try require(AudioHardwareCreateAggregateDevice(spec as CFDictionary,&device))
            lastSample=0
            try require(AudioDeviceCreateIOProcIDWithBlock(&proc,device,queue) { [weak self] _,input,_,_,_ in
                guard let self else { return }
                let now=CACurrentMediaTime();guard now-self.lastSample>=0.05 else { return };self.lastSample=now
                var sums=[Double](repeating:0,count:4),counts=[Int](repeating:0,count:4)
                for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input)) {
                    guard let data=buffer.mData else { continue }
                    let samples=data.assumingMemoryBound(to:Float.self),count=Int(buffer.mDataByteSize)/MemoryLayout<Float>.size
                    for i in 0..<count { let v=Double(samples[i]);if v.isFinite { let bin=min(3,i*4/max(1,count));sums[bin]+=v*v;counts[bin]+=1 } }
                }
                receive((0..<4).map { IslandWaveformRules.amplitude(sums[$0],count:counts[$0]) })
            })
            try require(AudioDeviceStart(device,proc))
        } catch { stop();throw error }
    }
    func stop() {
        if device != 0,let proc { AudioDeviceStop(device,proc);AudioDeviceDestroyIOProcID(device,proc) }
        proc=nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device);device=0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap);tap=0 }
    }
    private func require(_ status:OSStatus) throws { if status != noErr { throw NSError(domain:NSOSStatusErrorDomain,code:Int(status)) } }
}
@MainActor final class IslandAudioWaveform:ObservableObject {
    static let shared=IslandAudioWaveform()
    @Published private(set) var levels=[Double](repeating:0,count:4)
    @Published private(set) var active=false
    @Published private(set) var message="Off. Enable it to request system-audio access."
    private var tap:IslandAudioTap?
    private var receiving=false,locked=false,failed=false
    private var generation=UUID()
    private var timeout:Task<Void,Never>?
    var enabled:Bool { UserDefaults.standard.bool(forKey:"island.media.liveWaveform") }
    func setEnabled(_ value:Bool) { failed=false;UserDefaults.standard.set(value,forKey:"island.media.liveWaveform");configure() }
    func setLocked(_ value:Bool) { locked=value;configure() }
    func configure() {
        guard enabled else { stop();message="Off. Enable it to request system-audio access.";return }
        guard !locked,MusicManager.shared.isPlaying,!IslandSnooze.shared.active else { stop();if !failed { message="Waiting for playback. Capture pauses when music stops or your Mac locks." };return }
        guard tap==nil,!failed else { return }
        let token=UUID();generation=token;receiving=false;message="Waiting for system audio…"
        let capture=IslandAudioTap();tap=capture
        do {
            try capture.start { [weak self] values in Task { @MainActor in
                guard let self,self.generation==token,self.tap != nil else { return }
                self.receiving=true;self.active=true;self.message="Receiving audio locally. Nothing is saved or uploaded."
                self.levels=IslandWaveformRules.smooth(self.levels,incoming:values)
            } }
            timeout=Task { @MainActor [weak self] in
                try? await Task.sleep(for:.seconds(8));guard !Task.isCancelled,let self,self.generation==token,!self.receiving else { return }
                self.stop();self.failed=true;self.message="No audio received. Review System Audio Recording access, then try again while audio is playing."
            }
        } catch { stop();failed=true;message="The waveform couldn’t start. Review system-audio access, then try again. (\((error as NSError).code))" }
    }
    func retry() { failed=false;stop();configure() }
    func stop() { generation=UUID();timeout?.cancel();timeout=nil;tap?.stop();tap=nil;receiving=false;active=false;levels=[Double](repeating:0,count:4) }
}
struct IslandLiveWaveform:View {
    var playing:Bool
    @ObservedObject private var audio=IslandAudioWaveform.shared
    @ObservedObject private var focus=IslandSystemSounds.shared
    @AppStorage("island.media.focusSymbol") private var focusSymbol=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        Group {
            if focusSymbol,focus.sharedFocus==true { Image(systemName:"moon.fill").foregroundStyle(.purple).accessibilityLabel("Shared Focus is on") }
            else if playing,audio.active,!reduceMotion {
                HStack(alignment:.center,spacing:2) { ForEach(0..<4,id:\.self) { i in Capsule().fill(.cyan).frame(width:2,height:2+12*audio.levels[i]) } }.frame(width:16,height:16).accessibilityLabel("Live audio waveform")
            } else { Image(systemName:playing ? "waveform" : "pause.fill").foregroundStyle(.cyan).accessibilityLabel(playing ? "Playing" : "Paused") }
        }
    }
}
struct IslandWaveformSettings:View {
    @ObservedObject private var audio=IslandAudioWaveform.shared
    var body:some View {
        Toggle("Live audio waveform",isOn:Binding(get:{ audio.enabled },set:{ audio.setEnabled($0) }))
        Text("Uses macOS system-audio capture to react to sound. It includes other audible apps, never uses your microphone, and saves or uploads nothing. Capture pauses when playback stops or the Mac locks.").font(.caption).foregroundStyle(.secondary)
        Text(audio.message).font(.caption).foregroundStyle(.secondary)
        if audio.enabled { HStack { Button("Try again") { audio.retry() };Button("Review audio access…") { if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) } } } }
    }
}
