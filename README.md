# matrix-modal.nvim

A Matrix "digital rain" effect in a floating window for Neovim, with an optional
decryption animation that resolves arbitrary text out of the rain.

- Falling-character rain with a bright head and a configurable fading trail
- A decryption mode (`:MatrixSay`) that scrambles, then locks text into place
- An optional `font = "block"` mode that decrypts text as large 5x7 block letters
- Six built-in themes and four character sets, plus full color/charset overrides
- Centered floating window that tracks terminal resizes
- Single-instance: repeated opens are no-ops; `q` / `<Esc>` (or `:MatrixStop`) closes it
- `:checkhealth matrix-modal`

## Requirements

- Neovim >= 0.10 (uses `vim.uv` and the modern highlight API)

## Installation

Local plugin (as used in this config) with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Christopherbilg/matrix-modal.nvim",
  cmd = { "Matrix", "MatrixStop", "MatrixToggle", "MatrixSay" },
  opts = {
    theme = "matrix",
    speed = 100,
    density = 0.01,
  },
}
```

Providing `opts` makes lazy.nvim call `require("matrix-modal").setup(opts)` automatically.

## Commands

| Command             | Description                                                              |
| ------------------- | ------------------------------------------------------------------------ |
| `:Matrix`           | Open the rain modal                                                      |
| `:MatrixStop`       | Close the modal                                                          |
| `:MatrixToggle`     | Toggle the modal                                                         |
| `:MatrixSay {text}` | Decrypt `{text}` out of the rain. `\n` in the argument becomes a newline |

Inside the modal, `q` or `<Esc>` closes it.

## Configuration

`setup()` is optional; sensible defaults apply. All fields, with their defaults:

```lua
require("matrix-modal").setup({
  theme = "matrix",        -- matrix | terminal-green | amber | magenta | neon-blue | monochrome
  chars = nil,             -- nil = theme default; or "ascii"|"katakana"|"binary"|"hex", a raw string, or a string[]
  speed = 50,              -- ms between animation frames
  density = 0.03,          -- 0.0-1.0 chance per column per frame to spawn a stream
  width = 0.85,            -- fraction of columns (<1) or absolute cell count (>=1)
  height = 0.85,           -- fraction of lines (<1) or absolute cell count (>=1)
  color = nil,             -- hex override for the bright head (defaults to the theme color)
  fade_colors = nil,       -- string[] hex overrides for the trailing characters
  reveal_duration = 2000,  -- ms for a :MatrixSay message to fully resolve
  text_padding = 1,        -- cells of rain-free margin around revealed text; 0 disables
  font = "block",          -- "block" | "normal"; "block" renders revealed text as large 5x7 block letters
  hold_duration = nil,     -- ms to hold a revealed message before auto-closing; nil = until dismissed
})
```

Calling `setup()` also re-applies the highlight groups when the colorscheme changes.

### Themes

| Theme                | Head color | Default charset |
| -------------------- | ---------- | --------------- |
| `matrix` _(default)_ | `#00FF41`  | katakana        |
| `terminal-green`     | `#33FF33`  | ascii           |
| `amber`              | `#FFB000`  | ascii           |
| `magenta`            | `#FF00FF`  | ascii           |
| `neon-blue`          | `#00CCFF`  | ascii           |
| `monochrome`         | `#FFFFFF`  | ascii           |

A theme sets `color`, `fade_colors`, and a default `chars`; any of these can be
overridden in `opts`.

### Character sets

`ascii`, `katakana` (half-width), `binary` (`0` / `1`), and `hex`. You can also pass a
raw string (`chars = "01アイウ"`) or an explicit array of single characters.

## Lua API

```lua
local mm = require("matrix-modal")
mm.start()                 -- open the rain
mm.stop()                  -- close
mm.toggle()
mm.say("Wake up, Neo.", { reveal_duration = 3000, hold_duration = 5000 })
mm.say("NEO", { font = "block" })  -- decrypt as large block letters
mm.get_theme()             -- active theme name
```

## Health

```vim
:checkhealth matrix-modal
```

Reports the Neovim version, `vim.uv` availability, whether `setup()` has run, the
active theme, and command registration.

## Notes

- The grid is one terminal cell per character. Message text passed to `:MatrixSay` is
  sanitized to single-width cells: full-width CJK, emoji, and tabs are replaced with
  spaces so they cannot shear the layout.
- Revealed text (`:MatrixSay`) keeps a `text_padding`-cell rain-free
  margin around it, so the rain appears to fall behind the message.
- `font = "block"` renders revealed text from an embedded 5x7 bitmap font (no external
  dependencies). It applies to `:MatrixSay`, or per call via
  `mm.say(text, { font = "block" })`. Text is word-wrapped to the window width; anything
  still too wide or tall is clipped, so block mode suits short messages.
- Only one modal exists at a time; `:Matrix` while one is open is a no-op.
