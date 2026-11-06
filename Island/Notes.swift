import SwiftUI
import Combine

@MainActor final class IslandNotesStore: ObservableObject {
    struct Note: Codable, Identifiable { var id:String; var title:String; var text:String; var modified:Date; var deleted:Date? }
    static let shared = IslandNotesStore()
    @Published var notes:[Note] = []
    @Published var selected = ""
    private let defaults = UserDefaults.standard
    init() {
        if let data = defaults.data(forKey:"island.notes.collection"), let saved = try? JSONDecoder().decode([Note].self,from:data) { notes = saved.filter { $0.deleted == nil || Date().timeIntervalSince($0.deleted!) < 30*86400 } }
        if notes.isEmpty {
            notes = [Note(id:UUID().uuidString,title:"Quick Note",text:defaults.string(forKey:"island.notes") ?? "",modified:Date())]
        }
        selected = notes.first(where: { $0.deleted == nil })?.id ?? ""; save()
    }
    var current:Note? { notes.first { $0.id == selected && $0.deleted == nil } }
    var active:[Note] { notes.filter { $0.deleted == nil } }
    var trash:[Note] { notes.filter { $0.deleted != nil } }
    func create() { let note = Note(id:UUID().uuidString,title:"New Note",text:"",modified:Date()); notes.insert(note,at:0); selected = note.id; save() }
    func update(title:String? = nil,text:String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == selected }) else { return }
        if let title { notes[index].title = title }; if let text { notes[index].text = text }; notes[index].modified = Date(); save()
    }
    func remove() { guard let index = notes.firstIndex(where: { $0.id == selected }) else { return }; notes[index].deleted = Date(); selected = active.first?.id ?? ""; save() }
    func restore(_ id:String) { guard let index = notes.firstIndex(where: { $0.id == id }) else { return }; notes[index].deleted = nil; selected = id; save() }
    private func save() { defaults.set(try? JSONEncoder().encode(notes),forKey:"island.notes.collection") }
}
struct IslandNotesView: View {
    @ObservedObject var store = IslandNotesStore.shared
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Menu {
                    ForEach(store.active) { note in Button(note.title.isEmpty ? "Untitled" : note.title) { store.selected = note.id } }
                    Divider(); Button("New note") { store.create() }
                    if !store.trash.isEmpty { Menu("Restore from trash") { ForEach(store.trash) { note in Button(note.title.isEmpty ? "Untitled" : note.title) { store.restore(note.id) } } } }
                } label: { Image(systemName:"note.text"); Text("Notes"); Image(systemName:"chevron.down").font(.caption) }.menuStyle(.borderlessButton).fixedSize()
                if store.current != nil { TextField("Title",text:Binding(get: { store.current?.title ?? "" },set: { store.update(title:$0) })).textFieldStyle(.plain) }
                Spacer()
                Button { store.create() } label: { Image(systemName:"plus") }.buttonStyle(.plain).help("New note")
                Button { store.remove() } label: { Image(systemName:"trash") }.buttonStyle(.plain).help("Move note to recoverable trash").disabled(store.current == nil)
            }
            if store.current != nil {
                TextEditor(text:Binding(get: { store.current?.text ?? "" },set: { store.update(text:$0) })).id(store.selected).font(.body).scrollContentBackground(.hidden).padding(7).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
            } else { Text("No notes. Add one with +, or restore a note from the menu.").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
        }.padding(.horizontal,12).frame(height:134)
    }
}
