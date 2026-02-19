import SwiftUI

@main
struct DispatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = DispatchViewModel()

    var body: some Scene {
        MenuBarExtra("Dispatch", systemImage: "point.3.connected.trianglepath.dotted") {
            DispatchMenuView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
