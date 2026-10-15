import Cocoa
import ServiceManagement

// MARK: - Launch at login -----------------------------------------------------

enum LoginItemManager {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func setEnabled(_ enabled: Bool) {
    if enabled {
      try? SMAppService.mainApp.register()
    } else {
      try? SMAppService.mainApp.unregister()
    }
  }
}

// MARK: - Preferences window -----------------------------------------------------

final class PreferencesWindowController: NSWindowController {
  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 110),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    window.title = "Preferences"
    window.center()
    // Keep the window around (rather than deallocating it) when the user
    // closes it, so re-opening "Preferences…" shows the same instance.
    window.isReleasedWhenClosed = false

    self.init(window: window)

    let checkbox = NSButton(
      checkboxWithTitle: "Start photos-vim-keys at login",
      target: self,
      action: #selector(toggleLaunchAtLogin))
    checkbox.state = LoginItemManager.isEnabled ? .on : .off
    checkbox.translatesAutoresizingMaskIntoConstraints = false

    let contentView = NSView()
    contentView.addSubview(checkbox)
    window.contentView = contentView

    NSLayoutConstraint.activate([
      checkbox.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      checkbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
    ])
  }

  @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
    LoginItemManager.setEnabled(sender.state == .on)
  }
}

// MARK: - Status bar item --------------------------------------------------------

/// The menu bar icon this background utility shows instead of a Dock icon —
/// its menu is the only way to reach Preferences or quit without a terminal.
final class StatusBarController {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private var preferencesWindowController: PreferencesWindowController?

  init() {
    statusItem.button?.image = NSImage(
      systemSymbolName: "keyboard", accessibilityDescription: "photos-vim-keys")

    let menu = NSMenu()
    let titleItem = menu.addItem(withTitle: "photos-vim-keys", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    menu.addItem(.separator())
    menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
      .target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
    statusItem.menu = menu
  }

  @objc private func showPreferences() {
    if preferencesWindowController == nil {
      preferencesWindowController = PreferencesWindowController()
    }
    NSApp.activate(ignoringOtherApps: true)
    preferencesWindowController?.showWindow(nil)
    preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
