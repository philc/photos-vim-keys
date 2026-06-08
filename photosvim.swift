import ApplicationServices
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
  /// Overrides the event's Unicode string. Needed for keys like Home/End,
  /// whose meaning AppKit's key-binding system reads from their (private-use-
  /// area) character rather than their key code — the physical key we're
  /// remapping from leaves the wrong character on the event otherwise.
  /// `nil` leaves whatever string the underlying event already carries.
  let unicodeScalar: UniChar?

  init(_ keyCode: Int, _ flags: CGEventFlags = [], unicodeScalar: UniChar? = nil) {
    self.keyCode = CGKeyCode(keyCode)
    self.flags = flags
    self.unicodeScalar = unicodeScalar
  }
}

/// Applies a `NativeKey`'s Unicode string override (if any) to the event
/// being sent in its place.
private func applyUnicodeOverride(_ scalar: UniChar?, to event: CGEvent) {
  guard var scalar = scalar else { return }
  withUnsafePointer(to: &scalar) {
    event.keyboardSetUnicodeString(stringLength: 1, unicodeString: $0)
  }
}

// AppKit's private-use-area characters for the Home/End "function keys" —
// what fn+←/fn+→ actually produce, and what Photos' key-binding-driven
// "jump to first/last photo" command recognizes.
private let homeFunctionKey: UniChar = 0xF729
private let endFunctionKey: UniChar = 0xF72B

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

// "gg" / "G" -- jump to the first / last photo in the grid (vim's "go to
// first/last line"). They're built from a deselect/jump/nudge sequence (see
// `goToFirstSequence`/`goToLastSequence` below) that only makes sense as a
// fresh single-photo selection, so in visual mode they're no-ops.
let nativeGoToFirst = NativeKey(kVK_Home, unicodeScalar: homeFunctionKey)  // fn+←  (Home)  jump to first photo
let nativeGoToLast = NativeKey(kVK_End, unicodeScalar: endFunctionKey)  // fn+→  (End)  jump to last photo
let nativeDeselectAll = NativeKey(kVK_ANSI_A, [.maskCommand, .maskAlternate])  // ⌘⌥A  deselect all

/// "gg"/"G" in normal mode don't just move the keyboard focus to the first/
/// last photo — they should *select* it and clear any prior multi-selection,
/// the way landing on a line in vim leaves the cursor there and nowhere else.
/// Photos doesn't have a single shortcut for that, so we compose one: clear
/// the selection, jump to the corner, then nudge onto the first/last photo
/// (which Home/End alone moves the focus past without selecting anything).
let goToFirstSequence = [nativeDeselectAll, nativeGoToFirst, nativeMoveRight]
let goToLastSequence = [nativeDeselectAll, nativeGoToLast, nativeMoveLeft]

/// Collapses a multi-item selection down to a single item: moving right then
/// back left lands the selection on whatever was at the "active" end of the
/// visual-mode selection — mirroring how vim's Esc leaves the cursor at the
/// end of a visual block rather than deselecting everything.
let collapseSelectionSequence = [nativeMoveRight, nativeMoveLeft]

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
  /// Swallow the original key entirely and, on its key-down, post a sequence
  /// of brand new native keystrokes instead — for actions that don't
  /// correspond 1:1 to the key the user pressed (e.g. Esc both leaves visual
  /// mode *and* collapses the selection, which takes two native keystrokes).
  case inject([NativeKey])
}

final class ModalController {
  private(set) var mode: Mode = .normal {
    didSet { indicator.setMode(mode) }
  }
  private let indicator = ModeIndicator()
  private var heldKeys: [CGKeyCode: Translation] = [:]

  /// Set after a bare "g" — vim's prefix for "go to" commands. Only "gg"
  /// (go to the first photo) means anything to us; any other follow-up key
  /// cancels it and is then decided as if "g" had never been pressed.
  private var pendingG = false

  func isTracking(_ keyCode: CGKeyCode) -> Bool {
    heldKeys[keyCode] != nil
  }

  func handle(event: CGEvent, type: CGEventType, keyCode: CGKeyCode) -> CGEvent? {
    let translation: Translation
    if type == .keyDown {
      translation = decide(for: keyCode, flags: event.flags)
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
      applyUnicodeOverride(native.unicodeScalar, to: event)
      event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      return event
    case .inject(let sequence):
      // Post the replacement on key-down only — the key-up follows the same
      // `.inject` translation (via `heldKeys`) and would otherwise post it twice.
      if type == .keyDown {
        postSyntheticKeySequence(sequence)
      }
      return nil
    }
  }

  /// Looks up how to translate `keyCode` for the current mode. May itself
  /// trigger a mode switch (e.g. "v" enters visual mode, "d" in visual
  /// mode deletes the selection and returns to normal mode).
  ///
  /// Handles the "g" prefix ahead of the per-mode switch so "gg"/"G" behave
  /// the same — modulo extending vs. moving the selection — in both modes.
  private func decide(for keyCode: CGKeyCode, flags: CGEventFlags) -> Translation {
    // Real keyboard events carry incidental flag bits (e.g. .maskNonCoalesced)
    // alongside the modifiers that actually matter, so compare against the
    // intersection rather than the raw flags — matching `isRelevantKeystroke`.
    let modifiers = flags.intersection(meaningfulModifiers)

    if pendingG {
      pendingG = false
      if Int(keyCode) == kVK_ANSI_G && modifiers.isEmpty {
        // gg — the deselect-all/jump/nudge sequence we compose this from
        // doesn't translate into "extend the selection", so just no-op there.
        return mode == .visual ? .swallow : .inject(goToFirstSequence)
      }
      // Not "gg" — fall through and decide this key as if "g" never happened.
    }
    if Int(keyCode) == kVK_ANSI_G {
      if modifiers.isEmpty {
        pendingG = true
        return .swallow
      }
      if modifiers == [.maskShift] {
        // G — same story as "gg" above: no sensible visual-mode equivalent.
        return mode == .visual ? .swallow : .inject(goToLastSequence)
      }
    }

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
      case kVK_ANSI_S: return .remap(nativeFavorite)
      case kVK_ANSI_D: return .remap(nativeDelete)
      case kVK_ANSI_E: return .remap(nativeEdit)

      default:
        return .passthrough
      }

    case .visual:
      switch Int(keyCode) {
      case kVK_Escape, kVK_ANSI_V:
        mode = .normal
        return .inject(collapseSelectionSequence)

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

/// A brief on-screen HUD message announcing a mode change, in the spirit of
/// vim's "-- VISUAL --" status-line message — shown near the bottom of the
/// screen and faded out automatically, since the menu bar may be hidden.
final class ModeIndicator {
  private static let padding = NSSize(width: 22, height: 12)
  private static let visibleDuration: TimeInterval = 1.1

  private let window: NSWindow
  private let container = NSView()
  private let label = NSTextField(labelWithString: "")
  private var dismissWorkItem: DispatchWorkItem?

  init() {
    label.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
    label.textColor = .white
    label.alignment = .center

    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
    container.layer?.cornerRadius = 10
    container.addSubview(label)

    window = NSWindow(
      contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.contentView = container
    window.alphaValue = 0
  }

  func setMode(_ mode: Mode) {
    DispatchQueue.main.async { [weak self] in
      self?.present(mode)
    }
  }

  private func present(_ mode: Mode) {
    label.stringValue = mode == .visual ? "-- VISUAL --" : "-- NORMAL --"
    label.sizeToFit()

    let size = NSSize(
      width: label.frame.width + Self.padding.width * 2,
      height: label.frame.height + Self.padding.height * 2)
    label.frame.origin = NSPoint(x: Self.padding.width, y: Self.padding.height)
    container.frame = NSRect(origin: .zero, size: size)

    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let origin = NSPoint(
        x: visible.midX - size.width / 2,
        y: visible.minY + visible.height * 0.08)
      window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    window.orderFrontRegardless()
    dismissWorkItem?.cancel()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.1
      window.animator().alphaValue = 1
    }

    let dismiss = DispatchWorkItem { [weak self] in
      guard let self else { return }
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.3
          self.window.animator().alphaValue = 0
        },
        completionHandler: { self.window.orderOut(nil) })
    }
    dismissWorkItem = dismiss
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: dismiss)
  }
}

// MARK: - Event tap --------------------------------------------------------------

/// Returns the frontmost app, but only if it's the one this layer targets.
private func frontmostTargetApp() -> NSRunningApplication? {
  guard let app = NSWorkspace.shared.frontmostApplication,
    app.bundleIdentifier == targetBundleID
  else {
    return nil
  }
  return app
}

/// Accessibility roles whose focus means "the user is typing free-form
/// text" — while one of these is focused we let every keystroke through
/// untouched, so search fields, renaming, captions, etc. aren't intercepted.
/// (Search fields report role `AXTextField` with a search subrole, so
/// `kAXTextFieldRole` already covers them — no separate case needed.)
private let textInputRoles: Set<String> = [
  kAXTextFieldRole as String,
  kAXTextAreaRole as String,
  kAXComboBoxRole as String,
]

/// Whether the currently focused UI element of `app` looks like a free-text
/// input. Bounded by a short messaging timeout so a slow or hung app can't
/// stall the event tap — which the system would otherwise disable as
/// unresponsive (we'd recover via `tapDisabledByTimeout`, but better to avoid
/// the hiccup).
private func isTextInputFocused(in app: NSRunningApplication) -> Bool {
  let axApp = AXUIElementCreateApplication(app.processIdentifier)
  AXUIElementSetMessagingTimeout(axApp, 0.15)

  var focused: AnyObject?
  guard
    AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused)
      == .success,
    let element = focused
  else {
    return false
  }

  var role: AnyObject?
  guard
    AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
      == .success,
    let roleString = role as? String
  else {
    return false
  }

  return textInputRoles.contains(roleString)
}

/// Posts a sequence of brand new native keystrokes (key-down + key-up each),
/// in order, tagged so our own tap passes them straight through instead of
/// reprocessing them.
private func postSyntheticKeySequence(_ natives: [NativeKey]) {
  guard let source = CGEventSource(stateID: .hidSystemState) else { return }
  for native in natives {
    for keyDown in [true, false] {
      guard
        let synthetic = CGEvent(
          keyboardEventSource: source, virtualKey: native.keyCode, keyDown: keyDown)
      else { continue }
      synthetic.flags = native.flags
      applyUnicodeOverride(native.unicodeScalar, to: synthetic)
      synthetic.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      synthetic.post(tap: .cghidEventTap)
    }
  }
}

/// Modifier keys we pay attention to — Caps Lock, the numeric pad, and other
/// incidental flags macOS reports don't change how we interpret a keystroke.
private let meaningfulModifiers: CGEventFlags = [
  .maskCommand, .maskControl, .maskAlternate, .maskShift,
]

/// Whether our modal layer should interpret this keystroke at all. Bare keys
/// always qualify; the only modified keystroke we care about is Shift+G
/// (vim's "go to last photo") — everything else (⌘-shortcuts, Shift+Arrow
/// for Photos' own native multi-select, …) passes straight through untouched.
private func isRelevantKeystroke(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
  let modifiers = flags.intersection(meaningfulModifiers)
  if modifiers.isEmpty { return true }
  return modifiers == [.maskShift] && Int(keyCode) == kVK_ANSI_G
}

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
    guard
      let app = frontmostTargetApp(),
      isRelevantKeystroke(flags: event.flags, keyCode: keyCode),
      !isTextInputFocused(in: app)
    else {
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

app.run()
