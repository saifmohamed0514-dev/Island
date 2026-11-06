//
//  NotchHomeView.swift
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

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView().drawingGroup().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: BoringViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: width
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            if MusicManager.shared.isPlayerIdle {
                HStack(spacing: 18) {
                    Image(systemName: "music.note").font(.system(size: 38)).foregroundStyle(.secondary).frame(width: 100, height: 112).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not Playing").font(.title2).fontWeight(.semibold)
                        Text("Your music will appear here.").foregroundStyle(.secondary)
                        Button("Open Music") { MusicManager.shared.openMusicApp() }.buttonStyle(.bordered)
                    }
                    Spacer()
                }
            } else {
                MusicPlayerView(albumArtNamespace: albumArtNamespace)
            }

            if Defaults[.showCalendar] {
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

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
    static var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32 else { return false }
        return url.host != nil && !feed.contains("TheBoredTeam")
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
    @Published var ringing = false
    @Published var soundError: String?
    private var clock: Timer?
    private var player: AVAudioPlayer?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, startClock: Bool = true) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "island.timer.state"), let saved = try? JSONDecoder().decode(IslandTimerState.self, from: data), saved.remaining.isFinite, saved.duration.isFinite, (60...86400).contains(saved.duration), (0...86400).contains(saved.remaining) { state = saved }
        if startClock {
            clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            tick()
        }
    }
    var label: String { let seconds = Int(ceil(state.remaining)); return String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    func save() { defaults.set(try? JSONEncoder().encode(state), forKey: "island.timer.state") }
    func tick() { if state.tick(at: Date()) { save(); ring() } }
    func toggle() { stopSound(); if state.deadline == nil { state.start(at: Date()) } else { state.pause(at: Date()) }; save() }
    func reset(minutes: Double = 25) { stopSound(); state.reset(seconds: minutes * 60); save() }
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
    @ObservedObject var timer = IslandFocusTimer.shared
    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 7)
                Circle().trim(from: 0, to: max(0, min(1, timer.state.remaining / timer.state.duration))).stroke(.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: timer.state.finished ? "checkmark" : "timer").font(.system(size: 30)).foregroundStyle(.orange)
            }.frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(timer.state.finished ? "Time for a break" : "Focus Timer").foregroundStyle(.secondary)
                Text(timer.label).font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                HStack { ForEach([5,15,25], id: \.self) { minute in Button("\(minute) min") { timer.reset(minutes: Double(minute)) }.buttonStyle(.bordered) } }
            }
            Spacer()
            VStack {
                if timer.ringing { Button("Stop ringing", systemImage: "bell.slash") { timer.stopSound() }.tint(.orange) }
                Button(action: timer.toggle) { Image(systemName: timer.state.deadline == nil ? "play.fill" : "pause.fill").font(.title2).padding(12) }.buttonStyle(.bordered).tint(.orange).accessibilityLabel(timer.state.deadline == nil ? "Start timer" : "Pause timer")
                Button("Reset") { timer.reset(minutes: timer.state.duration / 60) }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 12).frame(height: 134)
    }
}

struct IslandFocusSettings: View {
    @ObservedObject var timer = IslandFocusTimer.shared
    @AppStorage("island.timer.tone") var tone = "Glass"
    @AppStorage("island.timer.volume") var volume = 0.7
    @AppStorage("island.timer.repeat") var repeating = false
    @AppStorage("island.timer.work") var minutes = 25.0
    var body: some View {
        Form {
            Section("Focus") { Stepper("Duration: \(Int(minutes)) minutes", value: $minutes, in: 1...1440); Button("Apply duration and reset") { timer.reset(minutes: minutes) } }
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

struct IslandNotesView: View {
    @AppStorage("island.notes") var notes = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Label("Quick Note", systemImage: "note.text"); Spacer(); Text("Saved on this Mac").font(.caption).foregroundStyle(.secondary) }
            TextEditor(text: $notes).font(.body).scrollContentBackground(.hidden).padding(7).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }.padding(.horizontal, 12).frame(height: 134)
    }
}

struct IslandDashboardView: View {
    @ObservedObject var timer = IslandFocusTimer.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(context.date, style: .time).font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(context.date.formatted(.dateTime.weekday(.wide).month().day())).foregroundStyle(.secondary)
                    Text("Make room for what matters.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    dashboardButton(timer.state.deadline == nil ? "Start a focus session" : timer.label, icon: "timer", view: .focus)
                    dashboardButton(music.isPlaying ? music.songTitle : "Not Playing", icon: "music.note", view: .home)
                    dashboardButton("Capture a note", icon: "square.and.pencil", view: .notes)
                }.frame(width: 235)
            }.padding(14).frame(height: 134)
        }
    }
    func dashboardButton(_ title: String, icon: String, view: NotchViews) -> some View {
        Button { coordinator.currentView = view } label: { HStack { Image(systemName: icon); Text(title).lineLimit(1); Spacer(); Image(systemName: "chevron.right").font(.caption2) }.padding(7).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
    }
}

struct IslandProjectSettings: View {
    var body: some View {
        Form {
            Section("Island • Open Source") {
                Text("An independent GPL-3.0 fork of Island.")
                Text("This is a development preview. See FEATURE-STATUS.md in the source for implemented features and remaining work.").foregroundStyle(.secondary)
            }
            Section("Updates") {
                Label(IslandUpdateConfiguration.isConfigured ? "Signed update feed configured" : "Local preview — updates not configured", systemImage: "arrow.down.circle")
                Text("Set your GitHub repository and Sparkle public key using scripts/configure-updates.py, then rebuild. Release instructions are in docs/RELEASING.md.").foregroundStyle(.secondary)
            }
            Section("Displays and HUDs") { Text("General → Show on all displays places Island at the center of each display’s menu bar. HUDs → Replace system HUD controls volume and brightness overlays; macOS Accessibility approval is required.") }
        }.formStyle(.grouped)
    }
}
