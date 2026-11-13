import SwiftUI

struct IslandPluginActivityView:View {
    let event:IslandAgentBridge.Event
    @ObservedObject var bridge:IslandAgentBridge
    @Environment(\.dismiss) private var dismiss
    @State private var answer=""
    @State private var sent=false
    private var current:IslandAgentBridge.Event { bridge.events.first { $0.id==event.id } ?? event }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Label(current.providerName,systemImage:"sparkles").font(.headline);Spacer();Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(current.title).font(.title3.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
            if current.isQuestion {
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        ForEach(current.options ?? [],id:\.self) { option in
                            Button { answer=option } label: { HStack { Text(option).frame(maxWidth:.infinity,alignment:.leading);if answer==option { Image(systemName:"checkmark.circle.fill").foregroundStyle(.blue) } }.padding(.vertical,4) }.buttonStyle(.bordered).disabled(sent || !current.pending)
                        }
                        TextField("Your answer…",text:$answer,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...5).disabled(sent || !current.pending).accessibilityLabel("Answer this question")
                        if answer.utf8.count>8000 { Text("Keep your answer under 8 KB.").font(.caption).foregroundStyle(.red) }
                    }
                }
                TimelineView(.periodic(from:.now,by:1)) { _ in
                    HStack { Text(sent ? (current.resolution == "Answered" ? "Answer received by the plugin." : "Answer sent. Waiting for the plugin…") : current.pending ? "Choose an option or write your own answer." : current.resolution ?? "This question expired. Reply in the original chat.").font(.caption).foregroundStyle(.secondary);Spacer();Button("Send answer") { if bridge.answer(current,text:answer) { sent=true;IslandHaptics.play(.confirmation) } }.buttonStyle(.borderedProminent).disabled(sent || !current.pending || answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || answer.utf8.count>8000) }
                }
            } else {
                if let percent=current.percent { ProgressView(value:percent,total:100);Text("\(Int(percent))% · "+current.statusTitle).font(.caption).foregroundStyle(.secondary) }
                else { Label(current.statusTitle,systemImage:current.state == "completed" ? "checkmark.circle" : "ellipsis.circle").foregroundStyle(.secondary) }
                ScrollView { Text(current.message.isEmpty ? "The assistant will send another update when it reaches its next milestone." : current.message).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                Text("Last update: "+Date(timeIntervalSince1970:current.time).formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if let error=bridge.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            Text("Native tool and system approvals stay in the original app.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
