//
//  IslandFocus.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import AppKit
import AVFoundation
import UniformTypeIdentifiers
import Combine
import Defaults
import SwiftUI

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}


// Island additions. GPL-3.0; upstream notices remain in their original files.

struct IslandUpdateConfiguration {
    static var feedURL:URL? {
        let configured=Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String
        let dynamic=UserDefaults.standard.string(forKey:"island.updates.feed")
        guard let feed=configured ?? dynamic,let url=URL(string:feed),url.scheme == "https",url.host != nil,!feed.lowercased().contains("theboredteam") else { return nil }
        return url
    }
    static var isConfigured:Bool {
        guard feedURL != nil,let key=Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") as? String,let bytes=Data(base64Encoded:key),bytes.count == 32 else { return false }
        return true
    }
}

struct IslandTimerState: Codable {
    var duration: Double = 1500
    var remaining: Double = 1500
    var deadline: Date?
    var finished = false
    mutating func start(at now: Date) { if remaining <= 0 { remaining = duration }; finished = false; deadline = now.addingTimeInterval(remaining) }
    mutating func tick(at now: Date) -> Bool {
        guard let deadline else { return false }
        remaining = min(86400, max(0, deadline.timeIntervalSince(now)))
        if remaining <= 0 { self.deadline = nil; finished = true; return true }
        return false
    }
    mutating func pause(at now: Date) { _ = tick(at: now); deadline = nil }
    mutating func reset(seconds: Double) { duration = min(86400, max(60, seconds.isFinite ? seconds : 1500)); remaining = duration; deadline = nil; finished = false }
}

@MainActor final class IslandFocusTimer: ObservableObject {
    static let shared = IslandFocusTimer()
    @Published var state = IslandTimerState()
    @Published var showCompletion = false
    private var completionTask: Task<Void,Never>?
    @Published var ringing = false
    @Published var phase = "Focus"
    private var cycles = 0
    @Published var presets: [Int] = [5, 15, 25] { didSet { defaults.set(presets, forKey: "island.timer.presets") } }
    @Published var soundError: String?
    private var clock: Timer?
    private var player: AVAudioPlayer?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, startClock: Bool = true) {
        self.defaults = defaults
        phase = defaults.string(forKey: "island.timer.phase") ?? "Focus"
        cycles = max(0,min(1000000,defaults.integer(forKey: "island.timer.cycles")))
        presets = IslandPresetRules.sanitize(defaults.array(forKey: "island.timer.presets") as? [Int] ?? [5,15,25])
        if let data = defaults.data(forKey: "island.timer.state"), let saved = try? JSONDecoder().decode(IslandTimerState.self, from: data), saved.remaining.isFinite, saved.duration.isFinite, (60...86400).contains(saved.duration), (0...86400).contains(saved.remaining) { state = saved }
        if startClock {
            clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            tick()
        }
    }
    var label: String { let seconds = Int(ceil(state.remaining)); return String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    func save() { defaults.set(try? JSONEncoder().encode(state), forKey: "island.timer.state"); defaults.set(phase,forKey:"island.timer.phase"); defaults.set(cycles,forKey:"island.timer.cycles") }
    func tick() {
        if state.tick(at: Date()) {
            showCompletion = true
            completionTask?.cancel()
            completionTask = Task { [weak self] in
                try? await Task.sleep(for:.seconds(4))
                guard !Task.isCancelled else { return }; self?.showCompletion = false
            }
            ring()
            if defaults.bool(forKey: "island.timer.pomodoro") {
                let next = IslandCycleRules.next(phase: phase, completed: cycles, work: defaults.double(forKey:"island.timer.work"), short: defaults.double(forKey:"island.timer.break"), long: defaults.double(forKey:"island.timer.longBreak"))
                phase = next.phase; cycles = next.completed
                state.reset(seconds: next.minutes * 60); state.start(at: Date())
            }
            save()
        }
    }
    func toggle() { stopSound(); if state.deadline == nil { state.start(at: Date()) } else { state.pause(at: Date()) }; save() }
    func addPreset(_ minutes: Int) { presets = IslandPresetRules.sanitize(presets + [minutes]) }
    func removePreset(_ minutes: Int) { presets = IslandPresetRules.sanitize(presets.filter { $0 != minutes }) }
    func reset(minutes: Double = 25) { showCompletion = false; completionTask?.cancel(); stopSound(); phase = "Focus"; state.reset(seconds: minutes * 60); save() }
    func dismissCompletion() { showCompletion = false; stopSound(); state.finished = false; save() }
    func stopSound() { player?.stop(); player = nil; ringing = false }
    func ring(preview: Bool = false) {
        stopSound(); soundError = nil
        let tone = defaults.string(forKey: "island.timer.tone") ?? "Glass"
        guard tone != "Silent" else { return }
        let url: URL
        if tone == "Custom" { url = Self.soundDirectory.appendingPathComponent(defaults.string(forKey: "island.timer.customFile") ?? "missing") }
        else { url = URL(fileURLWithPath: "/System/Library/Sounds/\(tone).aiff") }
        do {
            let sound = try AVAudioPlayer(contentsOf: url)
            sound.volume = Float(min(1, max(0, defaults.object(forKey: "island.timer.volume") == nil ? 0.7 : defaults.double(forKey: "island.timer.volume"))))
            sound.numberOfLoops = !preview && defaults.bool(forKey: "island.timer.repeat") ? -1 : 0
            sound.prepareToPlay(); guard sound.play() else { throw CocoaError(.fileReadUnknown) }
            player = sound; ringing = !preview
        } catch { soundError = "Couldn’t play this ringtone. Choose another sound."; if !preview { NSSound.beep() } }
    }
    static var soundDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Island/Ringtones", isDirectory: true) }
    func importSound() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            _ = try AVAudioPlayer(contentsOf: source)
            try FileManager.default.createDirectory(at: Self.soundDirectory, withIntermediateDirectories: true)
            let filename = UUID().uuidString + "." + source.pathExtension
            let destination = Self.soundDirectory.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: source, to: destination)
            let previous = defaults.string(forKey: "island.timer.customFile")
            defaults.set(filename, forKey: "island.timer.customFile"); defaults.set("Custom", forKey: "island.timer.tone")
            if let previous, !previous.contains("/") { try? FileManager.default.removeItem(at: Self.soundDirectory.appendingPathComponent(previous)) }
            soundError = nil
        } catch { soundError = "This audio file couldn’t be imported." }
    }
}

struct IslandFocusView: View {
    @EnvironmentObject var vm: IslandViewModel
    @ObservedObject var timer = IslandFocusTimer.shared
    @AppStorage("island.timer.dialMax") var dialMax = 120.0
    @State private var showingPresets = false
    @State private var dialDrag = IslandDialDrag()
    var editable: Bool { timer.state.deadline == nil }
    var progress: Double { editable && !timer.state.finished ? min(1, timer.state.duration / (dialMax * 60)) : timer.state.remaining / timer.state.duration }
    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 7)
                ForEach(0..<12, id: \.self) { tick in Capsule().fill(.white.opacity(0.3)).frame(width: 2, height: 4).offset(y: -43).rotationEffect(.degrees(Double(tick) * 30)) }
                Circle().trim(from: 0, to: max(0, min(1, progress))).stroke(.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: timer.state.finished ? "checkmark" : "timer").font(.system(size: 28)).foregroundStyle(.orange)
                if editable {
                    Circle().fill(.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.4), radius: 3).offset(y: -51).rotationEffect(.degrees(progress * 360))
                }
            }
            .frame(width: 102, height: 102).padding(8).contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard editable else { return }
                if let minutes = dialDrag.value(x: event.location.x - 59, y: event.location.y - 59, current: timer.state.duration / 60, maximum: dialMax) { if minutes % 5 == 0 && Int(timer.state.duration / 60) != minutes { IslandHaptics.play(.boundary) };timer.reset(minutes: Double(minutes)) }

            }.onEnded { _ in if editable { IslandHaptics.play(.placement) };dialDrag = IslandDialDrag() })
            .accessibilityElement(children: .ignore).accessibilityLabel("Timer duration")
            .accessibilityValue("\(Int(timer.state.duration / 60)) minutes")
            .accessibilityHint(editable ? "Adjust to set a custom duration" : "Pause the timer to change its duration")
            .accessibilityAdjustableAction { direction in
                guard editable else { return }; timer.reset(minutes: min(1440, max(1, timer.state.duration / 60 + (direction == .increment ? 1 : -1))))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(timer.state.finished ? "Time for a break" : timer.phase == "Focus" ? "Focus Timer" : timer.phase).foregroundStyle(.secondary)
                Text(timer.label).font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                Text(editable ? "Drag the ring to set time" : "One thing at a time.").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(timer.presets, id: \.self) { minute in Button("\(minute)m") { IslandHaptics.play(.selection);timer.reset(minutes: Double(minute)) }.buttonStyle(.bordered).accessibilityLabel("\(minute) minute preset") }
                        Button { showingPresets = true } label: { Image(systemName: "plus") }.buttonStyle(.bordered).help("Add a preset")
                    }
                }.frame(maxWidth: 280)
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                if timer.ringing { Button("Stop ringing", systemImage: "bell.slash") { timer.dismissCompletion() }.tint(.orange) }
                Button(action: { IslandHaptics.play(.confirmation);timer.toggle() }) { Image(systemName: editable ? "play.fill" : "pause.fill").font(.title2).frame(width: 44,height: 40) }.buttonStyle(.bordered).tint(.orange).accessibilityLabel(editable ? "Start timer" : "Pause timer")
                Button("Reset") { IslandHaptics.play(.selection);timer.reset(minutes: timer.state.duration / 60) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 12).frame(height: 134)
        .popover(isPresented: $showingPresets) { IslandAddPresetView(timer: timer).padding(20).frame(width: 250) }
        .onChange(of: showingPresets) { vm.isBatteryPopoverActive = showingPresets }
        .onDisappear { vm.isBatteryPopoverActive = false }
    }
}
struct IslandAddPresetView: View {
    @ObservedObject var timer: IslandFocusTimer
    @State var minutes = 45
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save a preset").font(.headline)
            HStack { TextField("Minutes",value:$minutes,format:.number).textFieldStyle(.roundedBorder).frame(width:80); Text("minutes"); Stepper("Minutes",value:$minutes,in:1...1440).labelsHidden() }
            Button("Save preset") { timer.addPreset(minutes); dismiss() }.disabled(!(1...1440).contains(minutes) || timer.presets.contains(minutes) || timer.presets.count >= 12)
        }
    }
}

struct IslandFocusSettings: View {
    @ObservedObject var timer = IslandFocusTimer.shared
    @AppStorage("island.timer.tone") var tone = "Glass"
    @AppStorage("island.timer.volume") var volume = 0.7
    @AppStorage("island.timer.repeat") var repeating = false
    @AppStorage("island.timer.work") var minutes = 25.0
    @AppStorage("island.timer.dialMax") var dialMax = 120.0
    @AppStorage("island.timer.pomodoro") var pomodoro = false
    @AppStorage("island.timer.break") var breakMinutes = 5.0
    @AppStorage("island.timer.longBreak") var longBreakMinutes = 15.0
    @State private var presetMinutes = 45

    var body: some View {
        Form {
            Section("Focus") { Stepper("Duration: \(Int(minutes)) minutes", value: $minutes, in: 1...1440); Button("Apply duration and reset") { timer.reset(minutes: minutes) } }
            Section("Work / break cycles") {
                Toggle("Automatically alternate focus and breaks",isOn:$pomodoro)
                Stepper("Short break: \(Int(breakMinutes)) minutes",value:$breakMinutes,in:1...120)
                Stepper("Long break: \(Int(longBreakMinutes)) minutes",value:$longBreakMinutes,in:1...120)
                Text("When enabled, a long break follows every four focus sessions. Completion sounds follow your ringtone settings. Pause stops the current countdown.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Saved presets") {
                ForEach(timer.presets, id: \.self) { preset in
                    HStack { Text("\(preset) minutes"); Spacer(); Button("Remove", role: .destructive) { timer.removePreset(preset) }.disabled(timer.presets.count == 1) }
                }
                Stepper("New preset: \(presetMinutes) minutes", value: $presetMinutes, in: 1...1440)
                Button("Add preset") { timer.addPreset(presetMinutes) }.disabled(timer.presets.contains(presetMinutes) || timer.presets.count >= 12)
                Picker("Full ring duration", selection: $dialMax) { ForEach([30.0,60,90,120,180], id: \.self) { Text("\(Int($0)) minutes").tag($0) } }
                Text("Drag the ring while paused to set a duration. Arrow keys and VoiceOver can adjust it one minute at a time.").foregroundStyle(.secondary)
            }
            Section("Ringtone") {
                Picker("Sound", selection: $tone) { ForEach(["Glass", "Hero", "Ping", "Submarine", "Sosumi", "Custom", "Silent"], id: \.self) { Text($0).tag($0) } }
                Slider(value: $volume, in: 0...1) { Text("Alert volume") }
                Toggle("Ring until stopped", isOn: $repeating)
                HStack { Button("Import audio…") { timer.importSound() }; Button("Preview") { timer.ring(preview: true) }; Button("Stop") { timer.stopSound() } }
                if let error = timer.soundError { Text(error).foregroundStyle(.red) }
            }
            Section { Text("The timer survives relaunch and sleep. Its sound plays once across all connected displays. Silent mode keeps the completion visible.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).onDisappear { if !timer.ringing { timer.stopSound() } }
    }
}
