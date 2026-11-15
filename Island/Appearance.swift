import SwiftUI
import AppKit

struct IslandAppearancePreferences:Codable,Equatable {
    var outline="off"
    var compactOutline=false
    var outlineColor="blue"
    var widthAdjustment=0.0
    var notchlessStyle="pill"
    var grayscaleArtwork=false
    var clearArtwork=false
    var artworkGlare=false
    var pausedArtworkOpacity=0.65
    var hideTitleExtras=false
    var gradientProgress=false
    var progressiveBlur:Bool?=nil
    var elasticSurface:Bool?=nil
    mutating func normalize() {
        if !["off","contrast","color"].contains(outline) { outline="off" }
        if !["blue","green","purple","orange","pink","white"].contains(outlineColor) { outlineColor="blue" }
        if !["pill","notch"].contains(notchlessStyle) { notchlessStyle="pill" }
        widthAdjustment=widthAdjustment.isFinite ? min(120,max(-40,widthAdjustment)) : 0
        pausedArtworkOpacity=pausedArtworkOpacity.isFinite ? min(1,max(0.2,pausedArtworkOpacity)) : 0.65
    }
    func width(base:Double,physical:Double)->Double { max(max(0,physical),max(60,base+widthAdjustment)) }
    func title(_ value:String)->String {
        guard hideTitleExtras else { return value }
        let result=value.replacingOccurrences(of:#"\s*[\[(](?:official\s+)?(?:audio|video|lyrics|lyric video|music video|hd|4k)[\])]"#,with:"",options:[.regularExpression,.caseInsensitive]).trimmingCharacters(in:.whitespacesAndNewlines)
        return result.isEmpty ? value : result
    }
}
@MainActor final class IslandAppearanceStore:ObservableObject {
    static let shared=IslandAppearanceStore()
    @Published private(set) var preferences:IslandAppearancePreferences
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        var p=defaults.data(forKey:"island.appearance").flatMap { try? JSONDecoder().decode(IslandAppearancePreferences.self,from:$0) } ?? IslandAppearancePreferences()
        p.normalize();preferences=p
    }
    func set<T>(_ path:WritableKeyPath<IslandAppearancePreferences,T>,_ value:T) {
        var p=preferences;p[keyPath:path]=value;p.normalize();guard p != preferences else { return }
        preferences=p;defaults.set(try? JSONEncoder().encode(p),forKey:"island.appearance")
        NotificationCenter.default.post(name:Notification.Name("NotchHeightChanged"),object:nil)
    }
    func restore(_ value:IslandAppearancePreferences) { var p=value;p.normalize();preferences=p;defaults.set(try? JSONEncoder().encode(p),forKey:"island.appearance");NotificationCenter.default.post(name:Notification.Name("NotchHeightChanged"),object:nil) }
    func binding<T>(_ path:WritableKeyPath<IslandAppearancePreferences,T>)->Binding<T> { Binding(get:{ self.preferences[keyPath:path] },set:{ self.set(path,$0) }) }
    var color:Color {
        switch preferences.outlineColor { case "green":return .green;case "purple":return .purple;case "orange":return .orange;case "pink":return .pink;case "white":return .white;default:return .blue }
    }
}

struct IslandGradientSlider:View {
    @Binding var value:Double
    let upperBound:Double
    var onEditingChanged:(Bool)->Void
    var colors:[Color]=[.cyan,.blue,.purple]
    @State private var dragging=false
    private var fraction:Double { upperBound>0 && value.isFinite ? min(1,max(0,value/upperBound)) : 0 }
    var body:some View {
        GeometryReader { geometry in
            ZStack(alignment:.leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height:5)
                Capsule().fill(LinearGradient(colors:colors,startPoint:.leading,endPoint:.trailing)).frame(width:geometry.size.width*fraction,height:5)
                Circle().fill(.white).frame(width:14,height:14).offset(x:max(0,geometry.size.width-14)*fraction)
            }.frame(height:18).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { event in
                if !dragging { dragging=true;onEditingChanged(true) }
                value=min(max(0,event.location.x/max(1,geometry.size.width)),1)*max(0,upperBound)
            }.onEnded { _ in dragging=false;onEditingChanged(false) })
        }.frame(height:18).environment(\.layoutDirection,.leftToRight)
        .accessibilityElement().accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(max(0,value))) of \(Int(max(0,upperBound))) seconds")
        .accessibilityAdjustableAction { direction in
            onEditingChanged(true);value=min(max(0,value+(direction == .increment ? 5 : -5)),max(0,upperBound));onEditingChanged(false)
        }
    }
}
struct IslandAppearanceSettings:View {
    @ObservedObject private var appearance=IslandAppearanceStore.shared
    var body:some View {
        Form {
            Section {
                HStack(spacing:16) {
                    Image(systemName:"capsule.portrait.fill").font(.system(size:30)).foregroundStyle(appearance.color)
                    VStack(alignment:.leading,spacing:4) { Text("Make it feel like your Mac.").font(.title2.weight(.semibold));Text("A black Island, a quiet outline, and details you choose.").foregroundStyle(.secondary) }
                }.padding(.vertical,10)
            }
            Section("Island shape") {
                Picker("Displays without a camera notch",selection:appearance.binding(\.notchlessStyle)) { Text("Pill").tag("pill");Text("Simulated notch").tag("notch") }
                Slider(value:appearance.binding(\.widthAdjustment),in:-40...120,step:1) { Text("Extra width") }
                Text("\(Int(appearance.preferences.widthAdjustment)) points · the physical camera always stays covered.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Motion") { Toggle("Soft blur while opening and closing",isOn:Binding(get:{ appearance.preferences.progressiveBlur ?? false },set:{ appearance.set(\.progressiveBlur,$0) }));Toggle("Gentle spring overshoot",isOn:Binding(get:{ appearance.preferences.elasticSurface ?? false },set:{ appearance.set(\.elasticSurface,$0) }));Text("Reduce Motion takes priority. Both choices keep the expanded controls on a fixed canvas.").font(.caption).foregroundStyle(.secondary) }
            Section("Outline") {
                Picker("Style",selection:appearance.binding(\.outline)) { Text("None").tag("off");Text("Soft contrast").tag("contrast");Text("Color").tag("color") }
                if appearance.preferences.outline == "color" { Picker("Color",selection:appearance.binding(\.outlineColor)) { ForEach(["blue","green","purple","orange","pink","white"],id:\.self) { Text($0.capitalized).tag($0) } } }
                Toggle("Also outline the closed Island",isOn:appearance.binding(\.compactOutline)).disabled(appearance.preferences.outline == "off")
            }
            Section("Artwork and progress") {
                Toggle("Grayscale artwork",isOn:appearance.binding(\.grayscaleArtwork))
                Toggle("Clear artwork background",isOn:appearance.binding(\.clearArtwork))
                Toggle("Soft artwork glare",isOn:appearance.binding(\.artworkGlare))
                Slider(value:appearance.binding(\.pausedArtworkOpacity),in:0.2...1,step:0.05) { Text("Artwork opacity while paused") }
                Toggle("Simplify common video title labels",isOn:appearance.binding(\.hideTitleExtras))
                Toggle("Gradient playback progress",isOn:appearance.binding(\.gradientProgress))
            }
            Section { Text("Settings follow the Mac’s appearance and accessibility choices. The Island stays black; glass belongs to Settings and pop-ups.").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}

struct IslandContentReveal:ViewModifier {
    var radius:CGFloat
    var opacity:Double
    func body(content:Content)->some View { content.blur(radius:radius).opacity(opacity) }
}
