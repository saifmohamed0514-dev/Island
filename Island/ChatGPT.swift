import SwiftUI

// Supported ChatGPT desktop deep links. Drafts are opened for review, never submitted.
enum IslandChatGPTLinks {
    static func draft(_ text:String)->URL? { guard text.utf8.count<=16000 else { return nil };var url=URLComponents();url.scheme="codex";url.host="new";url.queryItems=[URLQueryItem(name:"prompt",value:text)];return url.url }
    static func session(_ id:String)->URL? { guard UUID(uuidString:id) != nil else { return nil };return URL(string:"codex://threads/"+id) }
}
struct IslandChatGPTDraft:View {
    @State var text=""
    @State var status=""
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack { Image(systemName:"sparkle").foregroundStyle(.cyan);Text("ChatGPT").font(.headline);Spacer();Button("Continue in ChatGPT") { open() }.disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            TextField("Draft a question…",text:$text,axis:.vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            Text(status.isEmpty ? "Opens a draft in the desktop app for you to review and send." : status).font(.caption2).foregroundStyle(.secondary)
        }
    }
    func open() {
        guard let url=IslandChatGPTLinks.draft(text) else { status="Keep drafts under 16 KB.";return }
        guard NSWorkspace.shared.urlForApplication(toOpen:url) != nil else { status="Install the ChatGPT desktop app to open a draft. You can copy your text and use chatgpt.com instead.";return }
        if !NSWorkspace.shared.open(url) { status="Couldn’t open ChatGPT. Check that the desktop app is installed." }
    }
}
