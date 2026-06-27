import SwiftUI

@main
struct StacklightApp: App {
    @StateObject private var monitor = StackMonitor()

    var body: some Scene {
        MenuBarExtra {
            StacklightView()
                .environmentObject(monitor)
                .frame(width: 560, height: 620)
                .task {
                    monitor.startLoop()
                }
        } label: {
            StackMark(
                availableCount: monitor.availableCount,
                totalCount: monitor.totalCount,
                size: 18,
                showsStatusLights: true
            )
        }
        .menuBarExtraStyle(.window)
    }
}
