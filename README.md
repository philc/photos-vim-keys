# photos-vim-keys

A modal, vim-style keyboard layer for Photos.app on macOS.

## Build & run

```sh
make run        # builds and launches ./photos-vim-keys
```

This keyboard layer is only active while **Photos.app is frontmost**.

Whenever the mode changes, a small `-- NORMAL --` / `-- VISUAL --` HUD message flashes near the
bottom of the screen.

`photos-vim-keys` runs as a menu bar app. In Preferences, it can be set to start at login.

### Permissions

Creating a session-level event tap requires Accessibility access. The first time you run it, macOS
will either prompt you or `photos-vim-keys` will print an error and exit. If so, open **System
Settings → Privacy & Security → Accessibility** (and, on some macOS versions, **Input Monitoring**
too) and enable the binary (or the terminal app you launched it from — permissions are inherited
from the parent process). Re-run after granting access.

## Bindings

### Normal mode

| Key     | Action                                   |
|---------|------------------------------------------|
| `h j k l` | move selection left / down / up / right |
| `gg`    | jump to the first photo                  |
| `G`     | jump to the last photo                   |
| `C-u` / `C-d` | move selection 5 rows up / down    |
| `u`     | undo                                     |
| `R`     | redo                                     |
| `v`     | enter visual mode                        |
| `f`     | toggle favorite                          |
| `d`     | delete photo (→ Recently Deleted)        |
| `e`     | open / edit photo                        |
| `/`     | search                                   |

### Visual mode (`-- VISUAL --`)

| Key       | Action                                          |
|-----------|-------------------------------------------------|
| `h j k l` | extend selection left / down / up / right       |
| `C-u` / `C-d` | extend selection 5 rows up / down           |
| `u`       | undo                                            |
| `R`       | redo                                            |
| `f`       | toggle favorite for the whole selection         |
| `d`       | delete the selection, return to normal mode     |
| `Esc` / `v` | leave visual mode, collapsing the selection to a single item |

## Implementation notes

`photos-vim-keys` installs a `CGEventTap` on the session event stream. While Photos.app is
frontmost, unmodified key presses are run through a modal state machine (`ModalController`) and
either:

- **passed through** untouched (if the key is not bound),
- **swallowed** (mode-switch keys like `v` never reach Photos),
- **remapped** in place to one of Photos' own native shortcuts — e.g. `j` becomes Down-arrow.

Before intercepting a key-down, `photos-vim-keys` asks the Accessibility API which UI element is
focused in Photos (`isTextInputFocused`). If it's a text field, text area, or combo box,t hen
photos-vim-keys passes through the input.

## License

[MIT](LICENSE)
