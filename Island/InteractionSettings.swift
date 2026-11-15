import SwiftUI
import Defaults
struct IslandGestureSettings:View {
 @Default(.enableGestures) private var enabled
 @Default(.gestureSensitivity) private var sensitivity
 @Default(.openNotchOnHover) private var hover
 @AppStorage("island.gesture.middleCycle") private var middle=true
 @AppStorage("island.gesture.skip") private var skip=true
 @AppStorage("island.gesture.dismiss") private var dismiss=true
 @AppStorage("island.gesture.natural") private var natural=true
 @AppStorage("island.gesture.downCycle") private var downCycle=true
 @AppStorage("island.gesture.optionActions") private var optionActions=true
 @AppStorage("island.live.hidePaused") private var hidePaused=false
 var body:some View {
  Form {
   Section("Everyday actions") {
    Toggle("Expand on hover",isOn:$hover)
    Toggle("Swipe to open and close",isOn:$enabled)
    Toggle("Middle-click to cycle activities",isOn:$middle)
    Toggle("Option-click for alternate actions",isOn:$optionActions)
    Text("Option-click music to play or pause. Option-click another activity to cycle. Duo’s two sides each open their own tool.").font(.caption).foregroundStyle(.secondary)
   }
   Section("Trackpad") {
    Toggle("Swipe music to skip tracks",isOn:$skip)
    Toggle("Use natural swipe direction",isOn:$natural).disabled(!skip)
    Toggle("Swipe up to hide an activity for now",isOn:$dismiss).disabled(!enabled)
    Toggle("Swipe down while open to cycle activities",isOn:$downCycle).disabled(!enabled)
    Slider(value:$sensitivity,in:5...100,step:1) { Text("Open and close threshold") }
    Text("A larger threshold needs a longer swipe. Swipe down while closed to restore hidden activities. In the opened player, swipe on artwork so sliders and text keep their normal behavior.").font(.caption).foregroundStyle(.secondary)
   }
   Section("Quiet moments") { Toggle("Hide music activity while paused",isOn:$hidePaused);Text("The full player stays available. Your idle choice is in Trays.").font(.caption).foregroundStyle(.secondary) }
  }.formStyle(.grouped)
 }
}
