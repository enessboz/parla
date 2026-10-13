import SwiftUI

@main
@MainActor
struct EnglishPracticeApp: App {
    @State private var practice = PracticeViewModel()
    @State private var store = DataStore()

    init() {
        // A SwiftPM executable starts as a background process; make it a regular app with a Dock icon.
        DispatchQueue.main.async { NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(practice)
                .environment(store)
                .frame(minWidth: 820, minHeight: 560)
        }

        Settings { SettingsView() }
    }
}
