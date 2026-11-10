import SwiftUI
import Combine

struct IslandSavedLayout:Codable,Equatable,Identifiable {
    let id:UUID
    var name:String
    var snapshot:IslandDesignerSnapshot
}
@MainActor final class IslandSavedLayoutStore:ObservableObject {
    static let shared=IslandSavedLayoutStore()
    static let limit=12
    @Published private(set) var layouts:[IslandSavedLayout]=[]
    @Published private(set) var lastDeleted:IslandSavedLayout?
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        let saved=defaults.data(forKey:"island.layouts.saved").flatMap { try? JSONDecoder().decode([IslandSavedLayout].self,from:$0) } ?? []
        var ids=Set<UUID>()
        for var layout in saved {
            layout.name=Self.cleanName(layout.name)
            guard Self.validName(layout.name),ids.insert(layout.id).inserted,!layouts.contains(where:{ $0.name.compare(layout.name,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame }),layouts.count<Self.limit else { continue }
            layout.snapshot.modules.normalize();layout.snapshot.canvas.normalize();layouts.append(layout)
        }
        lastDeleted=defaults.data(forKey:"island.layouts.deleted").flatMap { try? JSONDecoder().decode(IslandSavedLayout.self,from:$0) }
    }
    static func cleanName(_ value:String)->String { value.trimmingCharacters(in:.whitespacesAndNewlines) }
    static func validName(_ value:String)->Bool { !value.isEmpty && value.count<=40 && !value.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) }
    @discardableResult func save(name:String,snapshot:IslandDesignerSnapshot,replacing id:UUID?=nil)->String? {
        let name=Self.cleanName(name)
        guard Self.validName(name) else { return "Choose a name with 1–40 characters." }
        guard !layouts.contains(where:{ $0.id != id && $0.name.compare(name,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame }) else { return "That name is already saved. Choose another, or update the existing layout." }
        var snapshot=snapshot;snapshot.modules.normalize();snapshot.canvas.normalize()
        if let id {
            guard let index=layouts.firstIndex(where:{ $0.id == id }) else { return "This layout is no longer available." }
            layouts[index]=IslandSavedLayout(id:id,name:name,snapshot:snapshot)
        } else {
            guard layouts.count<Self.limit else { return "You can save up to 12 layouts. Remove one before adding another." }
            layouts.append(IslandSavedLayout(id:UUID(),name:name,snapshot:snapshot))
        }
        persist();return nil
    }
    @discardableResult func rename(_ id:UUID,to name:String)->String? {
        guard let layout=layouts.first(where:{ $0.id == id }) else { return "This layout is no longer available." }
        return save(name:name,snapshot:layout.snapshot,replacing:id)
    }
    func delete(_ id:UUID) {
        guard let index=layouts.firstIndex(where:{ $0.id == id }) else { return }
        lastDeleted=layouts.remove(at:index);persist()
    }
    @discardableResult func undoDelete()->String? {
        guard let deleted=lastDeleted else { return "There is no removed layout to restore." }
        guard layouts.count<Self.limit else { return "Remove a layout to make room for this one." }
        guard !layouts.contains(where:{ $0.id == deleted.id || $0.name.compare(deleted.name,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame }) else { return "A layout with that name already exists. Rename it before restoring this one." }
        layouts.append(deleted);lastDeleted=nil;persist();return nil
    }
    private func persist() {
        defaults.set(try? JSONEncoder().encode(layouts),forKey:"island.layouts.saved")
        if let lastDeleted { defaults.set(try? JSONEncoder().encode(lastDeleted),forKey:"island.layouts.deleted") }
        else { defaults.removeObject(forKey:"island.layouts.deleted") }
    }
}

struct IslandSavedLayoutsView:View {
    let snapshot:()->IslandDesignerSnapshot
    let apply:(IslandSavedLayout)->Void
    @ObservedObject private var store=IslandSavedLayoutStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var feedback=""
    @State private var renameTarget:IslandSavedLayout?
    @State private var renameText=""
    @State private var replaceTarget:IslandSavedLayout?
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack { Label("Saved layouts",systemImage:"rectangle.stack").font(.title2.weight(.semibold));Spacer();Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Form {
                Section("Keep this arrangement") {
                    Text("Save your four positions, enabled modules and opening module. Your notes, files, timer and account settings stay as they are.").foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:10) { TextField("Layout name",text:$name,prompt:Text("Work, Study, Evening…")).textFieldStyle(.roundedBorder).labelsHidden().accessibilityLabel("Name for the current layout").onSubmit(save);Button("Save current layout",action:save).disabled(IslandSavedLayoutStore.cleanName(name).isEmpty || store.layouts.count>=IslandSavedLayoutStore.limit) }
                    if !feedback.isEmpty { Text(feedback).font(.callout).foregroundStyle(.secondary).accessibilityLabel("Layout status: "+feedback) }
                }
                Section("Your layouts · \(store.layouts.count) of 12") {
                    if store.layouts.isEmpty { Text("Save one for work, another for a quieter day. You can switch from the Layouts menu.").foregroundStyle(.secondary) }
                    ForEach(store.layouts) { layout in
                        HStack(spacing:12) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(layout.name).font(.headline)
                                Text("\(layout.snapshot.canvas.modules.count) positions · \(layout.snapshot.modules.enabled.count) enabled modules").font(.caption).foregroundStyle(.secondary)
                                if layout.snapshot.modules.enabled.contains(.usage) { Text("Includes local app-use recording").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            Button("Use") { apply(layout);dismiss() }.accessibilityLabel("Use "+layout.name+" layout")
                            Menu {
                                Button("Update with current arrangement…") { replaceTarget=layout }
                                Button("Rename…") { renameText=layout.name;renameTarget=layout }
                                Button("Remove",role:.destructive) { store.delete(layout.id);feedback="Removed "+layout.name+". You can undo below." }
                            } label:{ Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for "+layout.name)
                        }.padding(.vertical,4)
                    }
                    if let deleted=store.lastDeleted { Button("Undo removal of "+deleted.name) { feedback=store.undoDelete() ?? "Layout restored." } }
                }
                Section { Text("Applying a layout changes which modules are enabled. It never approves permissions. If a schedule or system Focus switches layouts, it can replace your choice at its next change. Undo in the module editor restores your previous arrangement.").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
        }.frame(width:580,height:540)
        .alert("Rename layout",isPresented:Binding(get:{ renameTarget != nil },set:{ if !$0 { renameTarget=nil } })) {
            TextField("Layout name",text:$renameText)
            Button("Cancel",role:.cancel) { renameTarget=nil }
            Button("Save") { if let target=renameTarget { feedback=store.rename(target.id,to:renameText) ?? "Layout renamed." };renameTarget=nil }
        }
        .confirmationDialog("Replace the saved arrangement?",isPresented:Binding(get:{ replaceTarget != nil },set:{ if !$0 { replaceTarget=nil } }),titleVisibility:.visible) {
            Button("Update saved layout") { if let target=replaceTarget { feedback=store.save(name:target.name,snapshot:snapshot(),replacing:target.id) ?? "Saved layout updated." };replaceTarget=nil }
        } message: { Text("The current arrangement will replace this saved layout. Your files and module data are kept.") }
    }
    private func save() {
        if let error=store.save(name:name,snapshot:snapshot()) { feedback=error }
        else { feedback="Saved "+IslandSavedLayoutStore.cleanName(name)+". Choose it from Layouts whenever you need it.";name="";IslandHaptics.play(.confirmation) }
    }
}
