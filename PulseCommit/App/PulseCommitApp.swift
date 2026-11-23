import SwiftUI

@main
struct PulseCommitApp: App {
    @UIApplicationDelegateAdaptor(PulseCommitAppDelegate.self) private var appDelegate
    @StateObject private var container: AppContainer = AppContainer.shared
    @AppStorage("onboarding_completed") private var onboardingCompleted: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if onboardingCompleted {
                    RootTabView()
                        .environmentObject(container)
                } else {
                    OnboardingView(healthStore: container.healthStore)
                        .environmentObject(container)
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await container.handleAutomaticWorkoutLifecycleEvent() }
                }
            }
        }
    }
}
