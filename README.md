# photos-vim-keys

A modal, vim-style keyboard layer for Photos.app on macOS, built with a
`CGEventTap`.

## Build & run

```sh
make run        # builds and launches ./photos-vim-keys
make build
make clean
```

Whenever the mode changes, a small `-- NORMAL --` / `-- VISUAL --` HUD message
flashes near the bottom of the screen, vim status-line style, then fades out.
The layer is only active while **Photos.app is frontmost** — switch away and
your keyboard behaves normally.

To quit, press `Ctrl-C` in the terminal you launched it from (or `make run`),
or run `pkill photos-vim-keys` from another terminal.

### Permissions

Creating a session-level event tap requires Accessibility access. The first
time you run it, macOS will either prompt you or `photos-vim-keys` will print an
error and exit. If so, open **System Settings → Privacy & Security →
Accessibility** (and, on some macOS versions, **Input Monitoring** too) and
enable the binary (or the terminal app you launched it from — permissions are
inherited from the parent process). Re-run after granting access.

## Bindings

### Normal mode

| Key     | Action                                   |
|---------|------------------------------------------|
| `h j k l` | move selection left / down / up / right |
| `gg`    | jump to the first photo                  |
| `G`     | jump to the last photo                   |
| `u`     | undo                                     |
| `R`     | redo                                     |
| `v`     | enter visual mode                        |
| `f`     | toggle favorite                          |
| `d`     | delete photo (→ Recently Deleted)        |
| `e`     | open / edit photo                        |

### Visual mode (`-- VISUAL --`)

| Key       | Action                                          |
|-----------|-------------------------------------------------|
| `h j k l` | extend selection left / down / up / right       |
| `u`       | undo                                            |
| `R`       | redo                                            |
| `f`       | toggle favorite for the whole selection         |
| `d`       | delete the selection, return to normal mode     |
| `Esc` / `v` | leave visual mode, collapsing the selection to a single item |

## How it works

`photos-vim-keys` installs a `CGEventTap` on the session event stream. While
Photos.app is frontmost, unmodified key presses are run through a small modal
state machine (`ModalController`) and either:

- **passed through** untouched (anything not bound),
- **swallowed** (mode-switch keys like `v` / `Esc` never reach Photos),
- **remapped** in place to one of Photos' own native shortcuts — e.g. `j`
  becomes Down-arrow, and in visual mode it becomes Shift+Down to extend the
  grid selection, exactly as if you'd held Shift and pressed the arrow key
  yourself, or
- **swallowed and replaced** with an entirely different native keystroke
  sequence — e.g. `Esc` in visual mode is dropped and a synthetic
  Right-then-Left arrow press is posted in its place. Pressing an unmodified
  arrow key collapses a multi-item selection down to one item, and doing
  right-then-left lands on whichever photo was at the "active" end of the
  visual selection — mirroring how vim's Esc leaves the cursor at the end of
  a visual block rather than deselecting everything.

Synthetic events are tagged with a marker field (`eventSourceUserData`) so
the tap recognizes — and ignores — its own output rather than reprocessing it.
Key-ups are translated identically to their matching key-downs (tracked in
`heldKeys`) so the mode can never change mid-press and leave Photos with a
stuck modifier or stuck key.

### Typing into text fields

Before intercepting a key-down, `photos-vim-keys` asks the Accessibility API which
UI element is focused in Photos (`isTextInputFocused`). If it's a text field,
text area, or combo box — search fields, album/photo renaming, captions,
comments, etc. — every keystroke is passed through untouched, so `j`/`k`/`d`/…
type normally instead of getting reinterpreted as vim commands. (No manual
"insert mode" needed — Photos already needs Accessibility access for the tap
itself, so this piggybacks on the same permission.) The query is bounded by a
short messaging timeout so a slow Photos can't stall the tap.

## Customizing

Everything you'd want to tweak lives at the top of `photos-vim-keys.swift`:

- `targetBundleID` — which app the layer is active in.
- The `native*` constants — which actual Photos.app keystroke each action
  performs (adjust if a future macOS/Photos version changes its shortcuts).
- `ModalController.decide(for:)` — the key bindings themselves; add more
  cases here (e.g. a `kVK_ANSI_R` for "rotate") following the existing pattern.
