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

// Sample content only: previewing a module never starts a camera, timer or connection.
struct IslandModulePreview:View {
    let modules:[NotchViews]
    let selected:NotchViews
    var focusMinutes:Double=25
    var weatherCity:String="Your city"
    var fahrenheit=false
    let onSelect:(NotchViews)->Void
    let onDrop:(NotchViews,NotchViews?,Bool)->Bool
    @State private var targeted=false
    @State private var overflow=false
    var body:some View {
        GeometryReader { geometry in
            let scale=min(1,geometry.size.width/680)
            VStack(spacing:0) {
                HStack(spacing:0) {
                    HStack(spacing:3) {
                        ForEach(Array(modules.prefix(5))) { module in chip(module) }
                        if modules.count>5 {
                            Button { overflow.toggle() } label: { Image(systemName:"ellipsis").frame(width:28,height:28) }.buttonStyle(.plain).help("More modules · click to arrange")
                                .popover(isPresented:$overflow) {
                                    VStack(alignment:.leading,spacing:10) {
                                        Text("More modules").font(.headline)
                                        Text("Drag to reorder. Click for settings.").font(.caption).foregroundStyle(.secondary)
                                        ForEach(Array(modules.dropFirst(5))) { module in
                                            HStack { chip(module);Text(module.title);Spacer();Image(systemName:"line.3.horizontal").foregroundStyle(.secondary) }
                                                .contentShape(Rectangle()).onTapGesture { onSelect(module);overflow=false }
                                                .draggable(IslandModuleTransfer(module:module))
                                                .dropDestination(for:IslandModuleTransfer.self) { values,point in
                                                    guard values.count == 1 else { return false }
                                                    let accepted=onDrop(values[0].module,module,point.x>130);if accepted { overflow=false };return accepted
                                                }
                                        }
                                    }.padding(16).frame(width:290)
                                }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Color.clear.frame(width:130)
                    HStack(spacing:12) { Image(systemName:"pin");Image(systemName:"slider.horizontal.3");Image(systemName:"battery.100").font(.system(size:22)).overlay { Text("84").font(.system(size:8,weight:.bold)).foregroundStyle(.black).offset(x:-1) } }.foregroundStyle(.gray).frame(maxWidth:.infinity,alignment:.trailing).accessibilityHidden(true)
                }.frame(height:34)
                Rectangle().fill(.white.opacity(0.07)).frame(height:1).padding(.top,3)
                sample.frame(maxWidth:.infinity,maxHeight:.infinity).padding(.top,12)
            }
            .padding(.horizontal,20).padding(.bottom,12)
            .frame(width:680,height:216,alignment:.top)
            .background(.black).clipShape(IslandSurface(radius:30))
            .overlay { IslandSurface(radius:30).stroke(targeted ? .blue : .white.opacity(0.10),lineWidth:targeted ? 3 : 1).allowsHitTesting(false) }
            .foregroundStyle(.white).environment(\.colorScheme,.dark)
            .scaleEffect(scale,anchor:.topLeading)
            .frame(width:geometry.size.width,height:216*scale,alignment:.topLeading)
        }
        .aspectRatio(680.0/216.0,contentMode:.fit)
        .dropDestination(for:IslandModuleTransfer.self) { values,_ in guard values.count == 1 else { return false };let accepted=onDrop(values[0].module,nil,false);if accepted { overflow=false };return accepted } isTargeted: { targeted=$0 }
        .accessibilityLabel("Interactive Island preview. Drag modules here to add them. Click a module icon for settings.")
    }
    private func chip(_ module:NotchViews)->some View {
        Button { onSelect(module);overflow=false } label: {
            Image(systemName:module.icon).frame(width:28,height:26)
                .foregroundStyle(module == selected ? .white : .gray)
                .background(module == selected ? .white.opacity(0.12) : .clear,in:Capsule())
        }.buttonStyle(.plain).help(module.title+" · drag to arrange, click for settings").accessibilityLabel(module.title+" settings")
        .draggable(IslandModuleTransfer(module:module)) { Label(module.title,systemImage:module.icon).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) }
        .dropDestination(for:IslandModuleTransfer.self) { values,point in guard values.count == 1 else { return false };let accepted=onDrop(values[0].module,module,point.x>14);if accepted { overflow=false };return accepted }
    }
    @ViewBuilder private var sample:some View {
        switch selected {
        case .home:
            HStack(spacing:22) {
                RoundedRectangle(cornerRadius:22).fill(.cyan.opacity(0.16)).overlay { Image(systemName:"music.note").font(.system(size:36)).foregroundStyle(.cyan) }.frame(width:110,height:110)
                VStack(alignment:.leading,spacing:9) { Text("Your music, right here.").font(.title2.weight(.semibold));Text("Song title · Artist").foregroundStyle(.secondary);ProgressView(value:0.42).tint(.white);HStack(spacing:28) { Image(systemName:"backward.fill");Image(systemName:"play.fill");Image(systemName:"forward.fill") }.font(.title3).padding(.top,5) }.frame(maxWidth:.infinity,alignment:.leading)
            }.padding(.horizontal,12)
        case .focus:
            HStack(spacing:24) { ZStack { Circle().stroke(.orange.opacity(0.15),lineWidth:6);Circle().trim(from:0,to:0.72).stroke(.orange,style:StrokeStyle(lineWidth:6,lineCap:.round)).rotationEffect(.degrees(-90));Text("\(Int(focusMinutes.isFinite ? min(1440,max(1,focusMinutes)) : 25)):00").font(.system(size:23,weight:.semibold,design:.rounded)).monospacedDigit() }.frame(width:98,height:98);VStack(alignment:.leading,spacing:9) { Text("A little room to focus.").font(.title2.weight(.semibold));Text("Your timer, presets and sounds.").foregroundStyle(.secondary);Label("Focus",systemImage:"play.fill").font(.headline).padding(.top,6) };Spacer() }.padding(.horizontal,18)
        case .weather:
            HStack(spacing:24) { Image(systemName:"sun.max.fill").font(.system(size:55,weight:.light)).foregroundStyle(.yellow).frame(width:110);VStack(alignment:.leading,spacing:8) { Text(weatherCity.isEmpty ? "Your city" : weatherCity).font(.title2.weight(.semibold)).lineLimit(1);Text(fahrenheit ? "75° · Clear" : "24° · Clear").font(.title.weight(.medium));Text("Sample forecast · change your city and units below").font(.caption).foregroundStyle(.secondary) };Spacer() }.padding(.horizontal,16)
        case .dashboard:
            HStack(spacing:10) { sampleCard("10:09",detail:"Today",icon:"clock");sampleCard("25 min",detail:"Focus",icon:"timer");sampleCard("Not Playing",detail:"Music",icon:"music.note");sampleCard("Quick Note",detail:"Notes",icon:"note.text") }.padding(.horizontal,4)
        case .shelf:
            VStack(spacing:10) { Image(systemName:"tray.and.arrow.down").font(.system(size:32)).foregroundStyle(.cyan);Text("A little space for your files.").font(.title3.weight(.semibold));Text("Drop files into your real Island tray.").foregroundStyle(.secondary) }
        default:
            HStack(spacing:22) {
                Image(systemName:selected.icon).font(.system(size:38,weight:.light)).foregroundStyle(.cyan).frame(width:90,height:90).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:22))
                VStack(alignment:.leading,spacing:8) { Text(selected.title).font(.title2.weight(.semibold));Text(IslandModuleGuide.description(selected)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3);Text("Preview · settings below").font(.caption).foregroundStyle(.cyan) };Spacer()
            }.padding(.horizontal,14)
        }
    }
    private func sampleCard(_ title:String,detail:String,icon:String)->some View {
        VStack(alignment:.leading,spacing:10) { Image(systemName:icon).foregroundStyle(.cyan);Text(title).font(.system(size:16,weight:.semibold)).lineLimit(1);Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(12).frame(height:112).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:16))
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
        case .agents:return "Local AI sessions and one-request approvals."
        case .inbox:return "Island alerts and notices you explicitly forward."
        }
    }
}
