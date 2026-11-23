import UIKit

@MainActor
final class PulseCommitAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppContainer.shared.automaticWorkoutObserverController?.registerSynchronouslyIfOptedIn()
        Task { await AppContainer.shared.handleAutomaticWorkoutLifecycleEvent() }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task { await AppContainer.shared.handleAutomaticWorkoutLifecycleEvent() }
    }
}
