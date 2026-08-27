import SwiftUI

@main
struct CMFSignalTraderApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            TabView {
                SignalView()
                    .tabItem { Label("Signal", systemImage: "waveform.path.ecg") }
                TraderView()
                    .tabItem { Label("Trader", systemImage: "arrow.left.arrow.right") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environmentObject(settings)
        }
    }
}
