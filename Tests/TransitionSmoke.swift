import Foundation
@main struct TransitionSmoke {
    @MainActor static func main() async throws {
        let vm=TransitionModel(),coordinator=IslandCoordinator.shared
        vm.open()
        precondition(vm.notchState == .open && vm.notchSize.width == openNotchSize.width && vm.notchSize.height == openNotchSize.height)
        vm.open();precondition(MusicManager.shared.updates == 1)
        vm.close();precondition(coordinator.currentView == .focus)
        await vm.pendingClose()?.value
        precondition(coordinator.currentView == .dashboard)

        coordinator.currentView = .focus;vm.open();vm.close()
        let cancelled=vm.pendingClose();precondition(cancelled != nil)
        coordinator.currentView = .notes;vm.open()
        await cancelled?.value
        precondition(coordinator.currentView == .notes && vm.notchState == .open)

        coordinator.currentView = .focus;vm.close()
        let firstClose=vm.pendingClose();vm.close()
        await firstClose?.value
        precondition(coordinator.currentView == .dashboard)

        vm.open();vm.isPinned=true;vm.close();precondition(vm.notchState == .open)
        vm.isPinned=false;vm.isEditingText=true;vm.close();precondition(vm.notchState == .open)
        vm.isEditingText=false;NSApp.modalWindow=1;vm.close();precondition(vm.notchState == .open)
        NSApp.modalWindow=nil;SharingStateManager.shared.preventNotchClose=true;vm.close();precondition(vm.notchState == .open)
        SharingStateManager.shared.preventNotchClose=false

        coordinator.currentView = .focus;coordinator.openLastTabByDefault=true;coordinator.showingCanvasDetail=true;vm.close()
        await vm.pendingClose()?.value
        precondition(coordinator.currentView == .focus && coordinator.showingCanvasDetail)
        coordinator.openLastTabByDefault=false;ShelfStateViewModel.shared.isEmpty=false;Defaults.shelfByDefault=true
        vm.open();vm.close();await vm.pendingClose()?.value
        precondition(coordinator.currentView == .shelf)
        IslandModuleStore.shared.enabled.remove(.shelf);coordinator.currentView = .focus
        vm.open();vm.close();await vm.pendingClose()?.value
        precondition(coordinator.currentView == .dashboard)
        vm.destroy()
        print("PASS: 13 production open/close lifecycle checks; deferred tab reset, rapid reopening, repeated close and editing/pin/modal/share guards; isolated dependencies")
    }
}
