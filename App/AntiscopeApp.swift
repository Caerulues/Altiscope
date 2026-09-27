import SwiftUI

@main struct AntiscopeApp: App {
    @StateObject private var recorder = Recorder()
    @StateObject private var preferences = MapPreferences()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(recorder).environmentObject(preferences)
                .preferredColorScheme(.dark).tint(Theme.accent)
        }
    }
}
