import UIKit
import GoogleSignIn


/// Handles app lifecycle events and Google Sign-In URL callbacks.
class AppDelegate: NSObject, UIApplicationDelegate {

    /// Called when the app finishes launching. Can be used for setup.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    /// Handles incoming URLs for Google Sign-In authentication.
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
