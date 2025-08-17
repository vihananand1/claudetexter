import Foundation
import GoogleSignIn

/// Manages Google authentication state for Gmail integration. Singleton for shared use.
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isSignedInToGmail = false
    
    /// Private initializer to enforce singleton pattern. Restores previous Google sign-in if available.
    private init() {
        restorePreviousSignIn()
    }

    /// Checks for previous Google sign-in and restores state if found.
    private func restorePreviousSignIn() {
        print(" Setting isSignedInToGmail in UserDefaults")
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let user = user {
                let token = user.accessToken.tokenString
                UserDefaults.standard.set(token, forKey: "gmailAccessToken")
                UserDefaults.standard.set(true, forKey: "isSignedInToGmail")
                self.isSignedInToGmail = true
                print("🔁 Restored previous Google Sign-In")
            } else {
                self.isSignedInToGmail = false
                print("🔁 No previous Google session found")
            }
        }
    }

    /// Signs out of Gmail and clears authentication state.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        UserDefaults.standard.removeObject(forKey: "gmailAccessToken")
        UserDefaults.standard.set(false, forKey: "isSignedInToGmail")
        isSignedInToGmail = false
        print("🚪 Signed out of Gmail")
    }
}
