import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / passcode lock when the app returns from the background.
@MainActor
@Observable
final class BiometricLock {
    private(set) var isLocked: Bool
    var lastError: String?

    static let enabledKey = "appLockEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey) && !UserDefaults.standard.bool(forKey: "uiDemo")
    }

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "קוד הגישה"
        }
    }

    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func unlock() async {
        guard isLocked else { return }
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "פתיחת הנתונים הפיננסיים שלך")
            if ok { isLocked = false; lastError = nil }
        } catch {
            lastError = "הזיהוי לא הצליח. נסה שוב."
        }
    }

    /// Verifies identity before turning the lock on.
    func enable() async -> Bool {
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "הפעלת נעילת אפליקציה")
            if ok { isEnabled = true }
            return ok
        } catch {
            lastError = "לא ניתן להפעיל נעילה במכשיר הזה."
            return false
        }
    }

    func disable() { isEnabled = false; isLocked = false }
}
