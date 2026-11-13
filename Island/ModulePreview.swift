import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let islandModule=UTType(exportedAs:"org.islandapp.module",conformingTo:.data)
}
struct IslandModuleTransfer:Codable,Transferable {
    let module:NotchViews
    static var transferRepresentation:some TransferRepresentation { CodableRepresentation(contentType:.islandModule) }
}

// These are sample module blocks in the same positions used by the real Island.
struct IslandModulePreview:View {
    let modules:[NotchViews]
    let slots:[NotchViews?]
    let selected:NotchViews
    var focusMinutes:Double=25
    var weatherCity:String="Your city"
    var fahrenheit=false
    let onSelect:(NotchViews)->Void
    let onDrop:(NotchViews,Int)->Bool
    @State private var target:Int?
    var body:some View {
        GeometryReader { geometry in
            let scale=min(1,geometry.size.width/680)
            VStack(spacing:0) {
                HStack(spacing:0) {
                    HStack(spacing:7) {
                        ForEach(Array(modules.prefix(5))) { module in
                            Button { onSelect(module) } label: {
                                Image(systemName:module.icon).frame(width:24,height:26).foregroundStyle(module == selected ? .white : .gray)
                                    .background(module == selected ? .white.opacity(0.10) : .clear,in:Capsule())
                            }.buttonStyle(.plain).help("Open "+module.title+" settings").accessibilityLabel(module.title+" settings")
                        }
                        if modules.count>5 {
                            Menu { ForEach(Array(modules.dropFirst(5))) { module in Button(module.title,systemImage:module.icon) { onSelect(module) } } } label: { Image(systemName:"ellipsis").frame(width:24) }
                                .menuStyle(.borderlessButton).help("More module settings").accessibilityLabel("More module settings")
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Color.clear.frame(width:130)
                    HStack(spacing:12) { Image(systemName:"pin");Image(systemName:"slider.horizontal.3");Image(systemName:"battery.100").font(.system(size:22)).overlay { Text("84").font(.system(size:8,weight:.bold)).foregroundStyle(.black).offset(x:-1) } }.foregroundStyle(.gray).frame(maxWidth:.infinity,alignment:.trailing).accessibilityHidden(true)
                }.frame(height:34)
                Rectangle().fill(.white.opacity(0.07)).frame(height:1).padding(.top,3)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                    ForEach(0..<4,id:\.self) { index in
                        Group {
                            if slots.indices.contains(index),let module=slots[index] {
                                Button { onSelect(module) } label: { block(module,index:index) }.buttonStyle(.plain)
                                    .draggable(IslandModuleTransfer(module:module)) { Label(module.title,systemImage:module.icon).padding(12).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) }
                                    .help(IslandCanvasPreferences.title(index)+" · drag this block to another position, or click for settings")
                                    .accessibilityLabel(module.title+" in "+IslandCanvasPreferences.title(index)+". Click for settings or drag to move.")
                            } else {
                                VStack(spacing:4) { Label("Drop a module here",systemImage:"plus").font(.system(size:13,weight:.medium));Text(IslandCanvasPreferences.title(index)).font(.caption).foregroundStyle(.secondary) }
                                    .frame(maxWidth:.infinity).frame(height:62).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:16))
                                    .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(Color.white.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[5])) }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius:16))
                        .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(target == index ? Color.blue : .clear,lineWidth:2).allowsHitTesting(false) }
                        .dropDestination(for:IslandModuleTransfer.self) { values,_ in guard values.count == 1 else { return false };return onDrop(values[0].module,index) } isTargeted: { if $0 { target=index } else if target == index { target=nil } }
                    }
                }.frame(width:640,height:134).padding(.top,12)
            }
            .padding(.horizontal,20).padding(.bottom,12).frame(width:680,height:216,alignment:.top)
            .background(.black).clipShape(IslandSurface(radius:30))
            .foregroundStyle(.white).environment(\.colorScheme,.dark)
            .scaleEffect(scale,anchor:.topLeading).frame(width:geometry.size.width,height:216*scale,alignment:.topLeading)
        }.aspectRatio(680.0/216.0,contentMode:.fit)
        .accessibilityLabel("Editable Island layout. Drop modules into the four spaces. Drag blocks between spaces. Click a block for settings.")
    }
    private func block(_ module:NotchViews,index:Int)->some View {
        HStack(spacing:12) {
            Image(systemName:module.icon).font(.system(size:21)).foregroundStyle(.cyan).frame(width:28)
            VStack(alignment:.leading,spacing:4) { Text(module.title).font(.caption).foregroundStyle(.secondary);Text(modules.contains(module) ? sampleValue(module) : "Off · click for settings").font(.system(size:14,weight:.medium,design:.rounded)).lineLimit(1).monospacedDigit() }
            Spacer(minLength:0);Image(systemName:"line.3.horizontal").font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal,14).frame(maxWidth:.infinity).frame(height:62)
        .background(module == selected ? .blue.opacity(0.15) : .white.opacity(0.055),in:RoundedRectangle(cornerRadius:16))
        .overlay { RoundedRectangle(cornerRadius:16).strokeBorder(module == selected ? Color.blue.opacity(0.75) : .white.opacity(0.08),lineWidth:1) }
    }
    private func sampleValue(_ module:NotchViews)->String {
        switch module {
        case .home:return "Not Playing"
        case .focus:return "\(Int(focusMinutes.isFinite ? min(1440,max(1,focusMinutes)) : 25)):00"
        case .shelf:return "Your files, close by"
        case .weather:return (fahrenheit ? "75° · " : "24° · ")+(weatherCity.isEmpty ? "Your city" : weatherCity)
        case .notes:return "Capture a thought"
        case .calendar:return "Your next event"
        case .tasks:return "Your reminders"
        case .system:return "CPU · memory · storage"
        case .day,.dashboard:return "10:09"
        case .agents:return "Your local sessions"
        case .inbox:return "Your Island alerts"
        default:return "Click for settings"
        }
    }
}

enum IslandModuleGuide {
    static func description(_ module:NotchViews)->String {
        switch module {
        case .dashboard:return "Four small widgets for the things you use most."
        case .home:return "Music, artwork and playback controls."
        case .shelf:return "Keep files close, then preview, share or move them."
        case .focus:return "A focus timer with custom presets, cycles and sounds."
        case .notes:return "Quick notes that save automatically on your Mac."
        case .weather:return "Your city, current conditions and the hours ahead."
        case .health:return "Gentle reminders to pause, move and recharge."
        case .system:return "CPU, memory and storage at a glance."
        case .usage:return "Local app-use counters. Records only while enabled."
        case .calendar:return "Your upcoming events, close at hand."
        case .tasks:return "Your reminders and a place to add the next task."
        case .day:return "A little perspective on the day and your schedule."
        case .launcher:return "Shortcuts to the apps and folders you choose."
        case .code:return "Code reviews and Jira issues from your accounts."
        case .translation:return "Translate with local Ollama or optional OpenAI."
        case .devices:return "Connected accessories and available battery levels."
        case .windows:return "Window layouts and optional edge snapping."
        case .files:return "Archive, convert, share and organize selected files."
        case .mirror:return "A camera preview, only when you start it."
        case .agents:return "Plugin progress and questions you can answer in Island."
        case .inbox:return "Island alerts and notices you explicitly forward."
        }
    }
}
