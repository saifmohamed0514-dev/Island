import SwiftUI
import Defaults
import LaunchAtLogin

enum OnboardingStep:Int,CaseIterable {
    case welcome,preferences,modules,permissions,finished
    var title:String { switch self { case .welcome:return "Welcome";case .preferences:return "Your preferences";case .modules:return "Your modules";case .permissions:return "Your permissions";case .finished:return "Ready" } }
    var next:OnboardingStep { OnboardingStep(rawValue:rawValue+1) ?? .finished }
    var previous:OnboardingStep { OnboardingStep(rawValue:rawValue-1) ?? .welcome }
}
struct OnboardingView:View {
    @State var step:OnboardingStep = .welcome
    let onFinish:()->Void
    @Default(.mediaController) private var source
    @Default(.showOnAllDisplays) private var allDisplays
    @Default(.openNotchOnHover) private var hover
    @AppStorage("island.windows.snap") private var snapping=false
    @ObservedObject private var setup=IslandPermissionSetup.shared
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                IslandMark(size:34)
                VStack(alignment:.leading,spacing:3) { Text("Make Island yours").font(.headline);Text(step.title).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("\(step.rawValue+1) of \(OnboardingStep.allCases.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.horizontal,24).padding(.vertical,16)
            HStack(spacing:5) { ForEach(OnboardingStep.allCases,id:\.rawValue) { item in Capsule().fill(item.rawValue<=step.rawValue ? Color.accentColor : Color.secondary.opacity(0.15)).frame(height:3) } }.padding(.horizontal,24)
            Group {
                switch step {
                case .welcome:WelcomeView { step = .preferences }
                case .preferences:preferences
                case .modules:
                    VStack(alignment:.leading,spacing:0) {
                        Text("Drag modules into the black preview. Click a module for its settings. Your changes apply to the real Island.").font(.callout).foregroundStyle(.secondary).padding(.horizontal,18).padding(.top,14)
                        IslandModuleDesigner()
                    }
                case .permissions:IslandPermissionsView(guidedSetup:true)
                case .finished:
                    VStack(spacing:22) {
                        Spacer();IslandMark(size:76);Text("Your Island is ready.").font(.largeTitle.weight(.semibold))
                        Text("Rest your pointer at the top of the screen to open Island. Click a module to use it; the grid button brings you back to your layout.").multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth:470)
                        Label("Change anything later in Settings",systemImage:"slider.horizontal.3").font(.callout)
                        Text("Skipped access stays off. Settings → Permissions helps you finish whenever you’re ready.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Spacer()
                    }.padding(30).frame(maxWidth:.infinity)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            Divider()
            HStack(spacing:12) {
                if step != .welcome { Button("Back") { step=step.previous }.disabled(setup.prompting) }
                Button(step == .finished ? "Close setup" : "Finish later") { finish() }.disabled(setup.prompting)
                Spacer()
                if step == .modules { Button("Choose modules later") { step = .permissions } }
                if step == .permissions {
                    Button("Continue") { setup.stop();step = .finished }.buttonStyle(.borderedProminent).disabled(setup.prompting)
                } else if step == .finished { Button("Start using Island") { finish() }.buttonStyle(.borderedProminent) }
                else if step != .welcome { Button("Continue") { step=step.next }.buttonStyle(.borderedProminent) }
            }.controlSize(.large).padding(18)
        }.frame(minWidth:720,minHeight:680)
    }
    private var preferences:some View {
        Form {
            Section {
                Text("A few things to make it feel at home.").font(.title2.weight(.semibold))
                Text("Pick what suits you. Every choice can be changed in Settings.").foregroundStyle(.secondary)
            }
            Section("Everyday") {
                LaunchAtLogin.Toggle("Open Island at login")
                Toggle("Open when the pointer rests on Island",isOn:$hover)
                Toggle("Show Island on every display",isOn:$allDisplays).onChange(of:allDisplays) { NotificationCenter.default.post(name:.showOnAllDisplaysChanged,object:nil) }
            }
            Section("Your player") {
                Picker("Music source",selection:$source) { ForEach(MediaControllerType.allCases) { Text($0.rawValue).tag($0) } }
                Text("Now Playing supports compatible apps and browsers. Apple Music and Spotify controls ask for access in the permissions step.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Snap windows when dragged to a screen edge",isOn:$snapping).onChange(of:snapping) { IslandWindowSnapping.shared.configure() }
                Text("See a layout preview at an edge, then release to place the window. This needs Window and system controls access, which comes next.").font(.caption).foregroundStyle(.secondary)
            }
            Section("You stay in control") { Text("Music, File Tray, Focus and Notes work without broad privacy access. Other modules explain what they need before you allow it. Nothing here requires full disk access.").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
    private func finish() {
        setup.stop()
        IslandCoordinator.shared.firstLaunch=false
        IslandCoordinator.shared.helloAnimationRunning=false
        onFinish()
    }
}
