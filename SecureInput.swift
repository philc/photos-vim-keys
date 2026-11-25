import Carbon.HIToolbox
import Cocoa
import IOKit

// MARK: - Secure Input warning ----------------------------------------------------

/// While any app has Secure Input on (typically while a password field has
/// focus), macOS hides keystrokes from event taps, so every binding silently
/// stops working. An app can leave it on by mistake after switching away, so
/// we warn whenever Photos comes to the front while it's on.
enum SecureInput {
  /// The name of the app holding Secure Input, read from the console-user
  /// entry WindowServer publishes in the IORegistry. `nil` if it can't be
  /// found.
  static func holderName() -> String? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    guard
      let users = IORegistryEntryCreateCFProperty(
        root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? [[String: Any]]
    else { return nil }
    for user in users {
      if let pid = (user["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value,
        let app = NSRunningApplication(processIdentifier: pid)
      {
        return app.localizedName
      }
    }
    return nil
  }

  /// Shows a warning on `hud` each time the target app is activated while
  /// Secure Input is on.
  static func warnOnActivation(of bundleID: String, hud: HUD) {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { notification in
      let app =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      guard app?.bundleIdentifier == bundleID, IsSecureEventInputEnabled() else { return }
      let holder = holderName() ?? "Another app"
      hud.show("Keys blocked: \(holder) has Secure Input on", for: 5)
    }
  }
}
