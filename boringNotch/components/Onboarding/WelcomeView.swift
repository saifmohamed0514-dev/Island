// Island welcome surface. Original project credits are retained in About and LICENSE.
import SwiftUI
struct WelcomeView:View {
    var onGetStarted:(()->Void)? = nil
    var body:some View {
        VStack(spacing:22) {
            Spacer(); IslandMark(size:94)
            Text("Welcome to Island").font(.system(size:28,weight:.semibold,design:.rounded))
            Text("A quiet home for music, focus and the tools you choose.").multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal,28)
            Spacer()
            Button("Make it yours") { onGetStarted?() }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("Open source. Yours to shape.").font(.caption).foregroundStyle(.secondary).padding(.bottom,32)
        }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
