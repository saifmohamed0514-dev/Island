// Island module navigation; original Boring Notch tab design by Hugo Persson.
import SwiftUI
struct TabSelectionView: View {
    @ObservedObject var coordinator = IslandCoordinator.shared
    @ObservedObject var modules = IslandModuleStore.shared
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(modules.enabled.prefix(5))) { module in
                Button { coordinator.showingCanvasDetail = module != .dashboard;coordinator.currentView = module } label: {
                    Image(systemName: module.icon).frame(width: 28, height: 26)
                        .foregroundStyle(coordinator.currentView == module ? .white : .gray)
                        .background(coordinator.currentView == module ? .white.opacity(0.10) : .clear, in: Capsule())
                }.buttonStyle(.plain).help(module.title).accessibilityLabel(module.title)
            }
            if modules.enabled.count > 5 {
                Menu { ForEach(Array(modules.enabled.dropFirst(5))) { module in Button(module.title, systemImage: module.icon) { coordinator.showingCanvasDetail = module != .dashboard;coordinator.currentView = module } } } label: { Image(systemName: "ellipsis").frame(width: 24) }.menuStyle(.borderlessButton).help("More modules")
            }
        }
    }
}
