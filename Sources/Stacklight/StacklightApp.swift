import SwiftUI

@main
struct StacklightApp: App {
    @StateObject private var monitor = StackMonitor()

    var body: some Scene {
        MenuBarExtra {
            StacklightView()
                .environmentObject(monitor)
                .frame(width: 540, height: 520)
                .task {
                    monitor.startLoop()
                }
        } label: {
            MenuBarStackMark(isAvailable: monitor.availableCount > 0)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStackMark: View {
    let isAvailable: Bool

    var body: some View {
        Text("S")
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 18, height: 18)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(isAvailable ? Color.green : Color.secondary)
                    .frame(width: 5, height: 5)
            }
            .accessibilityLabel("StackLight")
    }
}
