import SwiftUI

enum IslandTutorialLesson:Int,CaseIterable {
    case open,files,focus,arrange,explore
    var title:String { switch self { case .open:return "Open Island";case .files:return "Keep files close";case .focus:return "Make time for focus";case .arrange:return "Make it yours";case .explore:return "Explore your tools" } }
    var symbol:String { switch self { case .open:return "cursorarrow.rays";case .files:return "tray";case .focus:return "timer";case .arrange:return "square.grid.2x2";case .explore:return "sparkles" } }
}
struct IslandTutorialView:View {
    var onComplete:()->Void
    @State private var lesson=IslandTutorialLesson.open
    @State private var opened=false
    @State private var sampleFile=false
    @State private var minutes=25
    @State private var deadline:Date?
    @State private var dial=IslandDialDrag()
    @State private var layout=IslandCanvasPreferences(enabled:true,slots:[.home,.shelf,.focus,.notes])
    @State private var selected=NotchViews.home
    @State private var explored=NotchViews.calendar
    @State private var feedback=""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Label(lesson.title,systemImage:lesson.symbol).font(.title2.weight(.semibold));Spacer();Text("\(lesson.rawValue+1) / \(IslandTutorialLesson.allCases.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            HStack(spacing:5) { ForEach(IslandTutorialLesson.allCases,id:\.rawValue) { item in Capsule().fill(item.rawValue<=lesson.rawValue ? Color.accentColor : Color.secondary.opacity(0.15)).frame(height:3) } }
            Text("Practice here. This preview uses sample content and keeps your real files, timer and layout as they are.").font(.caption).foregroundStyle(.secondary)
            if lesson == .open && !opened {
                Button { openPreview() } label: { VStack(spacing:16) { Capsule().fill(.black).frame(width:190,height:38).overlay { Image(systemName:"waveform").foregroundStyle(.cyan) };Text("Hover over or click the practice Island").foregroundStyle(.secondary) }.frame(maxWidth:.infinity).frame(height:190) }.buttonStyle(.plain).onHover { if $0 { openPreview() } }.accessibilityLabel("Open the practice Island")
            } else {
                IslandModulePreview(modules:[.home,.shelf,.focus,.notes],slots:layout.slots,selected:selected,focusMinutes:Double(minutes),onSelect:{ module in selected=module;feedback=module.title+" selected. Click real module blocks to open their full controls.";IslandHaptics.play(.selection) },onDrop:{ module,index in guard layout.place(module,at:index) else { return false };selected=module;feedback="Position changed in the practice layout.";IslandHaptics.play(.placement);return true }).frame(maxWidth:680)
            }
            Group {
                switch lesson {
                case .open:
                    Text("On your Mac, rest the pointer over Island at the top edge to open it. You can also use Open Island from its menu, or your keyboard shortcut. Move away to close it; Pin keeps it open.").fixedSize(horizontal:false,vertical:true)
                case .files:
                    HStack(spacing:16) {
                        Image(systemName:sampleFile ? "doc.fill" : "tray.and.arrow.down").font(.system(size:30)).foregroundStyle(.blue)
                        VStack(alignment:.leading,spacing:6) { Text(sampleFile ? "Sample.pdf is in the practice tray" : "Drop a file onto your real Island").font(.headline);Text("File Tray keeps files within reach. Drag them out, use Quick Look, or share with AirDrop. Removing an item from the tray keeps the original file.").foregroundStyle(.secondary) }
                        Button(sampleFile ? "Remove sample" : "Add sample file") { sampleFile.toggle();IslandHaptics.play(.placement) }
                    }
                case .focus:
                    HStack(spacing:24) {
                        ZStack { Circle().stroke(.orange.opacity(0.15),lineWidth:6);Circle().trim(from:0,to:Double(minutes)/120).stroke(.orange,style:StrokeStyle(lineWidth:6,lineCap:.round)).rotationEffect(.degrees(-90));Text("\(minutes)m").font(.title3.monospacedDigit()) }.frame(width:88,height:88).contentShape(Circle())
                            .gesture(DragGesture(minimumDistance:0).onChanged { event in guard deadline == nil,let value=dial.value(x:event.location.x-44,y:event.location.y-44,current:Double(minutes),maximum:120) else { return };if value != minutes && value%5 == 0 { IslandHaptics.play(.boundary) };minutes=value }.onEnded { _ in dial=IslandDialDrag();IslandHaptics.play(.placement) })
                            .accessibilityLabel("Practice timer duration").accessibilityValue("\(minutes) minutes").accessibilityAdjustableAction { direction in minutes=min(120,max(1,minutes+(direction == .increment ? 1 : -1))) }
                        VStack(alignment:.leading,spacing:7) {
                            Text("Drag the ring to choose a time.").font(.headline)
                            Text("The real timer lets you save presets and choose ringtones in Focus & Sounds. A running timer stays beside the camera.").foregroundStyle(.secondary)
                            HStack { Button(deadline == nil ? "Start practice timer" : "Stop practice timer") { deadline=deadline == nil ? Date().addingTimeInterval(Double(minutes)*60) : nil;IslandHaptics.play(.confirmation) };if let deadline { Text(deadline,style:.timer).monospacedDigit().foregroundStyle(.orange) } }
                        }
                    }
                case .arrange:
                    Text("Drag a card into a position inside the preview. Drag an existing block to swap positions, or click it for settings. You’ll choose your real arrangement in the next step.").fixedSize(horizontal:false,vertical:true)
                    HStack { ForEach([NotchViews.home,.shelf,.focus,.notes]) { module in Label(module.title,systemImage:module.icon).font(.caption).padding(9).background(.quaternary,in:RoundedRectangle(cornerRadius:10)).draggable(IslandModuleTransfer(module:module)).accessibilityLabel("Drag "+module.title+" into the practice preview") } }
                    Text(feedback.isEmpty ? "Try moving File Tray to another space." : feedback).font(.caption).foregroundStyle(.secondary)
                case .explore:
                    Picker("Explore a module",selection:$explored) { ForEach(NotchViews.allCases) { module in Label(module.title,systemImage:module.icon).tag(module) } }
                    Text(IslandModuleGuide.description(explored)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                    Text("Start with what you use. Extra connections and permissions can be set up later. Settings has search, so typing a module name takes you straight to its options.").font(.callout)
                }
            }.font(.callout)
            Spacer(minLength:0)
            HStack { if lesson != .open { Button("Previous lesson") { lesson=IslandTutorialLesson(rawValue:lesson.rawValue-1) ?? .open;deadline=nil } };Spacer();Button(lesson == .explore ? "Choose my modules" : "Next lesson") { if lesson == .explore { onComplete() } else { lesson=IslandTutorialLesson(rawValue:lesson.rawValue+1) ?? .explore;opened=true;deadline=nil;selected=lesson == .files ? .shelf : lesson == .focus ? .focus : .home;IslandHaptics.play(.selection) } }.buttonStyle(.borderedProminent).controlSize(.large) }
        }.padding(22).animation(reduceMotion ? nil : .easeOut(duration:0.16),value:lesson)
    }
    private func openPreview() { guard !opened else { return };opened=true;IslandHaptics.play(.placement) }
}
