import Carbon.HIToolbox
import Cocoa

// MARK: - Configuration -------------------------------------------------------
//
// Edit the constants below to change which app this layer targets, which
// vim-style keys trigger which actions, and which native Photos.app
// keystrokes those actions get translated into.

/// Only intercept keystrokes while this app is frontmost.
let targetBundleID = "com.apple.Photos"

/// Tag stamped on every synthetic event we generate, so the tap recognizes —
/// and ignores — its own output instead of reprocessing it forever.
let syntheticMarker: Int64 = 0x5649_4D31  // "VIM1"

/// A native keystroke (key code + modifiers) that we ask Photos to perform.
struct NativeKey {
  let keyCode: CGKeyCode
  let flags: CGEventFlags
  init(_ keyCode: Int, _ flags: CGEventFlags = []) {
    self.keyCode = CGKeyCode(keyCode)
    self.flags = flags
  }
}

// Photos.app's own shortcuts that each action below is translated into.
// Adjust these if your version of Photos binds them differently.
let nativeMoveLeft = NativeKey(kVK_LeftArrow)
let nativeMoveRight = NativeKey(kVK_RightArrow)
let nativeMoveUp = NativeKey(kVK_UpArrow)
let nativeMoveDown = NativeKey(kVK_DownArrow)
let nativeExtendLeft = NativeKey(kVK_LeftArrow, .maskShift)
let nativeExtendRight = NativeKey(kVK_RightArrow, .maskShift)
let nativeExtendUp = NativeKey(kVK_UpArrow, .maskShift)
let nativeExtendDown = NativeKey(kVK_DownArrow, .maskShift)
let nativeFavorite = NativeKey(kVK_ANSI_Period)  // "."  toggle favorite
let nativeDelete = NativeKey(kVK_ForwardDelete, .maskCommand)  // ⌘⌫   delete photo
let nativeEdit = NativeKey(kVK_Return)  // ⏎   open / edit photo

// MARK: - Modes ----------------------------------------------------------------

enum Mode {
  case normal
  case visual
}

/// How a single physical key should be passed on to Photos. Decided once on
/// key-down and remembered, so the matching key-up is handled identically —
/// the mode (and thus the decision) can otherwise change mid-press.
enum Translation {
  case passthrough
  case swallow
  case remap(NativeKey)
}

final class ModalController {
  private(set) var mode: Mode = .normal {
    didSet { indicator.setMode(mode) }
  }
  private let indicator = ModeIndicator()
  private var heldKeys: [CGKeyCode: Translation] = [:]

  func isTracking(_ keyCode: CGKeyCode) -> Bool {
    heldKeys[keyCode] != nil
  }

  func handle(event: CGEvent, type: CGEventType, keyCode: CGKeyCode) -> CGEvent? {
    let translation: Translation
    if type == .keyDown {
      translation = decide(for: keyCode)
      heldKeys[keyCode] = translation
    } else {
      translation = heldKeys.removeValue(forKey: keyCode) ?? .passthrough
    }

    switch translation {
    case .passthrough:
      return event
    case .swallow:
      return nil
    case .remap(let native):
      event.setIntegerValueField(.keyboardEventKeycode, value: Int64(native.keyCode))
      event.flags = native.flags
      event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      return event
    }
  }

  /// Looks up how to translate `keyCode` for the current mode. May itself
  /// trigger a mode switch (e.g. "v" enters visual mode, "d" in visual
  /// mode deletes the selection and returns to normal mode).
  private func decide(for keyCode: CGKeyCode) -> Translation {
    switch mode {
    case .normal:
      switch Int(keyCode) {
      case kVK_ANSI_V:
        mode = .visual
        return .swallow

      // Movement, vim-style.
      case kVK_ANSI_H: return .remap(nativeMoveLeft)
      case kVK_ANSI_L: return .remap(nativeMoveRight)
      case kVK_ANSI_K: return .remap(nativeMoveUp)
      case kVK_ANSI_J: return .remap(nativeMoveDown)

      // Single-photo actions.
      case kVK_ANSI_F: return .remap(nativeFavorite)
      case kVK_ANSI_D: return .remap(nativeDelete)
      case kVK_ANSI_E: return .remap(nativeEdit)

      default:
        return .passthrough
      }

    case .visual:
      switch Int(keyCode) {
      case kVK_Escape, kVK_ANSI_V:
        mode = .normal
        return .swallow

      // Movement extends the selection (Shift+Arrow), vim-style.
      case kVK_ANSI_H: return .remap(nativeExtendLeft)
      case kVK_ANSI_L: return .remap(nativeExtendRight)
      case kVK_ANSI_K: return .remap(nativeExtendUp)
      case kVK_ANSI_J: return .remap(nativeExtendDown)

      // Acting on the whole selection.
      case kVK_ANSI_F:
        return .remap(nativeFavorite)
      case kVK_ANSI_D:
        mode = .normal
        return .remap(nativeDelete)

      default:
        return .passthrough
      }
    }
  }
}

// MARK: - Mode indicator --------------------------------------------------------

/// Tiny menu-bar readout of the current mode, in the spirit of vim's
/// "-- VISUAL --" status-line message.
final class ModeIndicator: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  override init() {
    super.init()
    statusItem.button?.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    let menu = NSMenu()
    menu.addItem(withTitle: "Quit Photos Vim", action: #selector(quit), keyEquivalent: "q")
    menu.items.last?.target = self
    statusItem.menu = menu
    setMode(.normal)
  }

  func setMode(_ mode: Mode) {
    let title = mode == .visual ? "-- VISUAL --" : "-- NORMAL --"
    DispatchQueue.main.async { [weak self] in
      self?.statusItem.button?.title = title
    }
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}

// MARK: - Event tap --------------------------------------------------------------

private func isTargetAppFrontmost() -> Bool {
  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundleID
}

/// Modifiers that take a keystroke out of our vim layer's hands entirely —
/// e.g. ⌘A "select all" should reach Photos untouched, not get reinterpreted.
private let passthroughModifiers: CGEventFlags = [
  .maskCommand, .maskControl, .maskAlternate, .maskShift,
]

private var eventTap: CFMachPort?

private func handleEvent(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  // The system disables a tap that's too slow to respond; just turn it back on.
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    return Unmanaged.passRetained(event)
  }

  guard type == .keyDown || type == .keyUp else {
    return Unmanaged.passRetained(event)
  }

  // Don't reprocess the synthetic keystrokes we generate ourselves.
  if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
    return Unmanaged.passRetained(event)
  }

  guard let refcon else { return Unmanaged.passRetained(event) }
  let controller = Unmanaged<ModalController>.fromOpaque(refcon).takeUnretainedValue()
  let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

  if type == .keyDown {
    guard isTargetAppFrontmost(), event.flags.intersection(passthroughModifiers).isEmpty else {
      return Unmanaged.passRetained(event)
    }
  } else {
    // Always finish translating a key-up that we started translating on
    // its key-down — even if focus moved away from Photos in between —
    // so Photos never ends up with a stuck modifier or a stuck key.
    guard controller.isTracking(keyCode) else {
      return Unmanaged.passRetained(event)
    }
  }

  guard let result = controller.handle(event: event, type: type, keyCode: keyCode) else {
    return nil
  }
  return Unmanaged.passRetained(result)
}

// MARK: - Bootstrap ---------------------------------------------------------------

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // background utility: no Dock icon, no app menu

let controller = ModalController()
let refcon = Unmanaged.passUnretained(controller).toOpaque()

let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

guard
  let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: handleEvent,
    userInfo: refcon
  )
else {
  FileHandle.standardError.write(
    Data(
      """
      Failed to create an event tap.

      Grant this binary access under System Settings -> Privacy & Security ->
      Accessibility (and, on some macOS versions, Input Monitoring too),
      then run it again.

      """.utf8))
  exit(1)
}

eventTap = tap
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print(
  """
  Photos Vim is running — look for "-- NORMAL --" in the menu bar.
  Switch to Photos.app and try:
    v            enter visual mode (selection-extending)
    h j k l      move / extend selection left, down, up, right
    f            toggle favorite
    d            delete (also exits visual mode)
    e            edit / open photo
    Esc or v     leave visual mode
  """)

app.run()
