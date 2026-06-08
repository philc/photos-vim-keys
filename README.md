# photosvim

A modal, vim-style keyboard layer for Photos.app on macOS, built with a
`CGEventTap`. No Xcode project, no Interface Builder — it's a single Swift
file compiled directly with `swiftc`.

## Build & run

```sh
make run        # builds (if needed) and launches ./photosvim
make build      # just builds
make clean      # removes the binary
```

`make build` produces a `photosvim` binary in the project directory; you can
also run it directly with `./photosvim` once built.

A small `-- NORMAL --` indicator appears in the menu bar. The layer is only
active while **Photos.app is frontmost** — switch away and your keyboard
behaves normally.

### Permissions

Creating a session-level event tap requires Accessibility access. The first
time you run it, macOS will either prompt you or `photosvim` will print an
error and exit. If so, open **System Settings → Privacy & Security →
Accessibility** (and, on some macOS versions, **Input Monitoring** too) and
enable the binary (or the terminal app you launched it from — permissions are
inherited from the parent process). Re-run after granting access.

Note: re-running `./build.sh` produces a new binary; macOS may ask you to
re-grant permission after a rebuild.

## Bindings

### Normal mode

| Key     | Action                                   |
|---------|------------------------------------------|
| `h j k l` | move selection left / down / up / right |
| `v`     | enter visual mode                        |
| `f`     | toggle favorite                          |
| `d`     | delete photo (→ Recently Deleted)        |
| `e`     | open / edit photo                        |

### Visual mode (`-- VISUAL --`)

| Key       | Action                                          |
|-----------|--------------------------------------------------|
| `h j k l` | extend selection left / down / up / right        |
| `f`       | toggle favorite for the whole selection           |
| `d`       | delete the selection, return to normal mode       |
| `Esc` / `v` | leave visual mode (selection stays as-is)       |

## How it works

`photosvim` installs a `CGEventTap` on the session event stream. While
Photos.app is frontmost, unmodified key presses are run through a small modal
state machine (`ModalController`) and either:

- **passed through** untouched (anything not bound),
- **swallowed** (mode-switch keys like `v` / `Esc` never reach Photos), or
- **remapped** in place to one of Photos' own native shortcuts — e.g. `j`
  becomes Down-arrow, and in visual mode it becomes Shift+Down to extend the
  grid selection, exactly as if you'd held Shift and pressed the arrow key
  yourself.

Synthetic events are tagged with a marker field (`eventSourceUserData`) so
the tap recognizes — and ignores — its own output rather than reprocessing it.
Key-ups are translated identically to their matching key-downs (tracked in
`heldKeys`) so the mode can never change mid-press and leave Photos with a
stuck modifier or stuck key.

## Customizing

Everything you'd want to tweak lives at the top of `photosvim.swift`:

- `targetBundleID` — which app the layer is active in.
- The `native*` constants — which actual Photos.app keystroke each action
  performs (adjust if a future macOS/Photos version changes its shortcuts).
- `ModalController.decide(for:)` — the key bindings themselves; add more
  cases here (e.g. a `kVK_ANSI_R` for "rotate") following the existing pattern.
