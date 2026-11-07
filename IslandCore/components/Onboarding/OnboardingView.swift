// Island's permission-light setup. Optional connections live in Settings.
import SwiftUI
import Defaults
enum OnboardingStep { case welcome,cameraPermission,calendarPermission,remindersPermission,accessibilityPermission,musicPermission,finished }
struct OnboardingView:View {
    @State var step:OnboardingStep = .welcome
    let onFinish:()->Void
    let onOpenSettings:()->Void
    @Default(.mediaController) var source
    var body:some View {
        VStack {
            if step == .welcome { WelcomeView { step = .musicPermission } }
            else if step == .musicPermission {
                VStack(alignment:.leading,spacing:22) {
                    IslandMark(size:60); Text("Bring your music.").font(.largeTitle.weight(.semibold))
                    Text("Choose a source. You can change it any time.").foregroundStyle(.secondary)
                    Picker("Player",selection:$source) { ForEach(MediaControllerType.allCases) { Text($0.rawValue).tag($0) } }
                    Text("The system player works with supported apps and browsers. Nothing is uploaded by Island.").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("Continue") { IslandCoordinator.shared.firstLaunch = false; IslandCoordinator.shared.helloAnimationRunning = false; step = .finished }.buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(34)
            } else {
                VStack(spacing:22) {
                    Spacer(); IslandMark(size:76); Text("Your Island is ready.").font(.title.weight(.semibold))
                    Text("Hover at the top of your screen. Add modules and connections when you need them.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Spacer(); Button("Set up permissions") { onFinish();IslandSettingsController.shared.showPermissions() }.buttonStyle(.bordered);Button("Choose modules",action:onOpenSettings).buttonStyle(.bordered); Button("Start using Island",action:onFinish).buttonStyle(.borderedProminent).controlSize(.large)
                }.padding(34)
            }
        }.frame(width:420,height:540)
    }
}
