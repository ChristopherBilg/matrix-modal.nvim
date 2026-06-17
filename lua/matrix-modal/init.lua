local M = {}

local block_font = require("matrix-modal.block_font")

math.randomseed(vim.uv.hrtime())

-- Splits a string into an array of single-codepoint strings (UTF-8 safe).
local function split_chars(s)
  return vim.fn.split(s, "\\zs")
end

-- Splits a string into single-display-column cells. Any character that would
-- occupy more (full-width CJK, emoji, tab) or fewer (combining marks) than one
-- terminal cell is replaced with a space so message text cannot shear the grid.
local function split_cells(s)
  local cells = {}
  for _, ch in ipairs(split_chars(s)) do
    cells[#cells + 1] = (vim.fn.strdisplaywidth(ch) == 1) and ch or " "
  end
  return cells
end

local CHARSETS = {
  ascii = split_chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&*"),
  katakana = split_chars(
    "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ"
  ),
  binary = { "0", "1" },
  hex = split_chars("0123456789ABCDEF"),
}

local THEMES = {
  matrix = {
    color = "#00FF41",
    fade_colors = { "#FFFFFF", "#C0FFC0", "#80FF80", "#40FF40" },
    chars = "katakana",
  },
  ["terminal-green"] = {
    color = "#33FF33",
    fade_colors = { "#E0FFE0", "#A0FFA0", "#66CC66", "#338833" },
    chars = "ascii",
  },
  amber = {
    color = "#FFB000",
    fade_colors = { "#FFFFFF", "#FFE6B0", "#FFCC80", "#FFB840" },
    chars = "ascii",
  },
  magenta = {
    color = "#FF00FF",
    fade_colors = { "#FFFFFF", "#FFC0FF", "#FF80FF", "#FF40FF" },
    chars = "ascii",
  },
  ["neon-blue"] = {
    color = "#00CCFF",
    fade_colors = { "#FFFFFF", "#C0E8FF", "#80D0FF", "#40B8FF" },
    chars = "ascii",
  },
  monochrome = {
    color = "#FFFFFF",
    fade_colors = { "#F0F0F0", "#C0C0C0", "#808080", "#404040" },
    chars = "ascii",
  },
}

local DEFAULTS = {
  speed = 50,
  density = 0.03,
  width = 0.85,
  height = 0.85,
  reveal_duration = 2000,
  text_padding = 1,
  font = "block",
}

-- Intentionally single-instance: timer/win/buf live on the module so
-- repeated M.start() calls no-op while a modal is open, and a single
-- M.stop() / M.toggle() manages the global state.
local timer = nil
local win = nil
local buf = nil
local ns = vim.api.nvim_create_namespace("MatrixFade")

---@alias MatrixModalThemeName "matrix"|"terminal-green"|"amber"|"magenta"|"neon-blue"|"monochrome"
---@alias MatrixModalCharsetName "ascii"|"katakana"|"binary"|"hex"

---@class MatrixModalConfig
---@field theme? MatrixModalThemeName Named color/charset bundle (default "matrix").
---@field chars? MatrixModalCharsetName|string|string[] Charset: named preset, raw string, or array. Omit to use theme default.
---@field speed? integer Milliseconds between animation frames.
---@field density? number Probability per column per frame of spawning a stream (0.0-1.0).
---@field color? string Hex color override for the head of each stream.
---@field width? number Window width: fraction (< 1) or absolute cell count (>= 1).
---@field height? number Window height: fraction (< 1) or absolute cell count (>= 1).
---@field fade_colors? string[] Hex color overrides for trailing characters.
---@field reveal_duration? integer Milliseconds for a decrypted message to fully resolve. Default 2000.
---@field text_padding? integer Cells of rain-free margin around :MatrixSay text. Default 1; 0 disables.
---@field font? "normal"|"block" Render :MatrixSay text as large 5x7 block letters. Default "block".
---@field hold_duration? integer Milliseconds to hold a revealed message before auto-closing. Nil = persist until dismissed.
local config = vim.tbl_deep_extend("force", DEFAULTS, THEMES.matrix, { theme = "matrix" })

-- Resolved char pool used by the hot path. Reset by setup() from config.chars.
local charset = CHARSETS.katakana

local function set_highlights()
  vim.api.nvim_set_hl(0, "MatrixModalBase", { fg = config.color, bold = true })
  vim.api.nvim_set_hl(0, "MatrixDecryptText", { fg = config.color, bold = true })
  for i, color in ipairs(config.fade_colors) do
    vim.api.nvim_set_hl(0, "MatrixModalFade" .. i, { fg = color, bold = true })
  end
end

local function resolve_charset(value)
  if type(value) == "table" then
    return value
  end
  if type(value) == "string" then
    return CHARSETS[value] or split_chars(value)
  end
  return CHARSETS.ascii
end

---@param opts? MatrixModalConfig
function M.setup(opts)
  opts = opts or {}
  local theme_name = opts.theme or "matrix"
  local theme = THEMES[theme_name]
  if not theme then
    vim.notify(("matrix-modal: unknown theme %q, falling back to 'matrix'"):format(theme_name), vim.log.levels.WARN)
    theme = THEMES.matrix
    theme_name = "matrix"
  end
  config = vim.tbl_deep_extend("force", DEFAULTS, theme, opts)
  config.theme = theme_name
  charset = resolve_charset(config.chars)
  set_highlights()
  local group = vim.api.nvim_create_augroup("MatrixModalHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = set_highlights,
  })
end

-- Returns the active theme name. Used by the healthcheck.
function M.get_theme()
  return config.theme
end

-- Read-only snapshot of resolved state for diagnostics and :checkhealth.
-- Never mutates anything.
function M.health_info()
  return {
    theme = config.theme,
    chars = config.chars,
    charset_size = #charset,
    speed = config.speed,
    density = config.density,
    width = config.width,
    height = config.height,
    reveal_duration = config.reveal_duration,
    text_padding = config.text_padding,
    font = config.font,
    hold_duration = config.hold_duration,
    color = config.color,
    fade_colors = vim.deepcopy(config.fade_colors or {}),
    themes = vim.tbl_keys(THEMES),
    charsets = vim.tbl_keys(CHARSETS),
  }
end

local function get_random_char()
  return charset[math.random(1, #charset)]
end

-- Fractions (< 1) scale by `total`; absolutes (>= 1) cap at `total`.
local function resolve_dim(value, total)
  if value < 1 then
    return math.floor(total * math.max(0.1, value))
  end
  return math.min(total, math.floor(value))
end

-- Centered float geometry derived from the current editor size and config.
local function compute_geometry()
  local width = resolve_dim(config.width, vim.o.columns)
  local height = resolve_dim(config.height, vim.o.lines)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  return width, height, row, col
end

-- A height x width grid pre-filled with single spaces.
local function build_grid(width, height)
  local grid = {}
  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      grid[y][x] = " "
    end
  end
  return grid
end

local function stop_timer()
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    timer = nil
  end
end

-- Builds the target overlay for a decryption animation.
-- Returns:
--   target:   nested map y -> x -> char (the message, positioned and clipped)
--   unlocked: flat array of {x, y, ch} used for random locking
--   count:    total number of target cells
--   blank:    flat array of {x, y} cells: the message bounding box grown by
--             config.text_padding and clamped to the grid, kept rain-free
local function build_target(text, grid_width, grid_height, block)
  -- In block mode the message is first rendered into a multi-line grid of
  -- solid blocks (word-wrapped to the grid width), then handled exactly like
  -- any other multi-line text: centered, clipped, and decrypted cell-by-cell.
  if block then
    text = block_font.render(text or "", grid_width, "█", " ")
  end
  local lines = vim.split(text or "", "\n", { plain = true })
  local line_chars = {}
  for _, line in ipairs(lines) do
    local chars = split_cells(line)
    while #chars > grid_width do
      table.remove(chars)
    end
    table.insert(line_chars, chars)
  end
  while #line_chars > grid_height do
    table.remove(line_chars)
  end

  local total_height = #line_chars
  local start_y = math.floor((grid_height - total_height) / 2) + 1

  local target = {}
  local unlocked = {}
  local count = 0
  local min_x, max_x, min_y, max_y
  for i, line in ipairs(line_chars) do
    local y = start_y + i - 1
    if y >= 1 and y <= grid_height then
      local line_width = #line
      local start_x = math.floor((grid_width - line_width) / 2) + 1
      for j, ch in ipairs(line) do
        local x = start_x + j - 1
        if x >= 1 and x <= grid_width then
          target[y] = target[y] or {}
          target[y][x] = ch
          table.insert(unlocked, { x = x, y = y, ch = ch })
          count = count + 1
          min_x = math.min(min_x or x, x)
          max_x = math.max(max_x or x, x)
          min_y = math.min(min_y or y, y)
          max_y = math.max(max_y or y, y)
        end
      end
    end
  end

  -- Rain-free margin: the message bounding box grown by text_padding and
  -- clamped to the grid. Empty when there is no text.
  local blank = {}
  if count > 0 then
    local pad = math.max(0, math.floor(config.text_padding or 0))
    local x0, x1 = math.max(1, min_x - pad), math.min(grid_width, max_x + pad)
    local y0, y1 = math.max(1, min_y - pad), math.min(grid_height, max_y + pad)
    for y = y0, y1 do
      for x = x0, x1 do
        blank[#blank + 1] = { x = x, y = y }
      end
    end
  end

  return target, unlocked, count, blank
end

local function _start_modal(mode)
  if win and vim.api.nvim_win_is_valid(win) then
    return
  end
  mode = mode or {}

  local width, height, row, col = compute_geometry()

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_set_option_value("winhl", "NormalFloat:MatrixModalBase", { win = win })

  local grid = build_grid(width, height)

  local streams = {}
  timer = assert(vim.uv.new_timer())

  local decrypt
  if mode.decrypt then
    local target, unlocked, count, blank = build_target(mode.decrypt.text, width, height, mode.decrypt.block)
    decrypt = {
      text = mode.decrypt.text,
      block = mode.decrypt.block,
      target = target,
      unlocked = unlocked,
      target_count = count,
      blank = blank,
      locked = {},
      locked_count = 0,
      -- Guard against a zero/nil duration: the reveal progress math divides by this.
      reveal_duration = math.max(1, mode.decrypt.reveal_duration or config.reveal_duration),
      hold_duration = mode.decrypt.hold_duration,
      reveal_start_ms = vim.uv.hrtime() / 1e6,
      reveal_complete_ms = nil,
    }
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = stop_timer,
  })

  -- Keep the modal centered and correctly sized when the terminal is resized.
  local resize_group = vim.api.nvim_create_augroup("MatrixModalResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = resize_group,
    callback = function()
      if not (win and vim.api.nvim_win_is_valid(win)) then
        return
      end
      width, height, row, col = compute_geometry()
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
      })
      grid = build_grid(width, height)
      streams = {}
      if decrypt then
        local was_complete = decrypt.reveal_complete_ms ~= nil
        local target, unlocked, count, blank = build_target(decrypt.text, width, height, decrypt.block)
        decrypt.target = target
        decrypt.unlocked = unlocked
        decrypt.target_count = count
        decrypt.blank = blank
        decrypt.locked = {}
        decrypt.locked_count = 0
        local now = vim.uv.hrtime() / 1e6
        if was_complete then
          -- Already resolved before the resize: re-lock at the new geometry so
          -- the message stays solid instead of replaying the decryption.
          for _, item in ipairs(unlocked) do
            decrypt.locked[item.y] = decrypt.locked[item.y] or {}
            decrypt.locked[item.y][item.x] = item.ch
          end
          decrypt.locked_count = count
          decrypt.unlocked = {}
          decrypt.reveal_complete_ms = now
        else
          -- Mid-reveal: restart the decryption at the new geometry.
          decrypt.reveal_start_ms = now
          decrypt.reveal_complete_ms = nil
        end
      end
    end,
  })

  timer:start(
    0,
    config.speed,
    vim.schedule_wrap(function()
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        stop_timer()
        return
      end

      for x = 1, width do
        if math.random() < config.density then
          table.insert(streams, {
            x = x,
            y = 0,
            length = math.random(5, height),
            speed = math.random(1, 3),
            tick = 0,
          })
        end
      end

      local next_streams = {}
      for _, s in ipairs(streams) do
        s.tick = s.tick + 1
        if s.tick >= s.speed then
          s.tick = 0
          local tail_y = s.y - s.length
          if tail_y > 0 and tail_y <= height then
            grid[tail_y][s.x] = " "
          end
          s.y = s.y + 1
          if s.y > 0 and s.y <= height then
            grid[s.y][s.x] = get_random_char()
          end
          for my = math.max(1, s.y - s.length + 1), math.min(height, s.y - 1) do
            if math.random() < 0.1 then
              grid[my][s.x] = get_random_char()
            end
          end
        end
        if s.y - s.length <= height then
          table.insert(next_streams, s)
        end
      end
      streams = next_streams

      if decrypt then
        local now = vim.uv.hrtime() / 1e6
        local progress = math.min(1.0, (now - decrypt.reveal_start_ms) / decrypt.reveal_duration)
        local desired = math.floor(decrypt.target_count * progress)
        while decrypt.locked_count < desired and #decrypt.unlocked > 0 do
          local idx = math.random(1, #decrypt.unlocked)
          local item = decrypt.unlocked[idx]
          decrypt.locked[item.y] = decrypt.locked[item.y] or {}
          decrypt.locked[item.y][item.x] = item.ch
          decrypt.locked_count = decrypt.locked_count + 1
          decrypt.unlocked[idx] = decrypt.unlocked[#decrypt.unlocked]
          decrypt.unlocked[#decrypt.unlocked] = nil
        end
        -- Keep a rain-free margin behind the text: blank the padded box, then
        -- draw the message on top.
        for _, cell in ipairs(decrypt.blank or {}) do
          grid[cell.y][cell.x] = " "
        end
        for ty, row_map in pairs(decrypt.target) do
          for tx, _ in pairs(row_map) do
            local lch = decrypt.locked[ty] and decrypt.locked[ty][tx]
            grid[ty][tx] = lch or get_random_char()
          end
        end
      end

      -- Grid cells can be multibyte (katakana is 3 bytes), so extmark columns
      -- must be byte offsets, not cell indices. Build a cell -> byte map per row
      -- alongside the rendered lines: byte_at[y][x] is the first byte of cell x,
      -- and byte_at[y][width + 1] is the end of the line.
      local lines = {}
      local byte_at = {}
      for y = 1, height do
        local row = grid[y]
        local cols = {}
        local acc = 0
        for x = 1, width do
          cols[x] = acc
          acc = acc + #row[x]
        end
        cols[width + 1] = acc
        byte_at[y] = cols
        lines[y] = table.concat(row)
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      for _, s in ipairs(streams) do
        for i = 1, #config.fade_colors do
          local fade_y = s.y - (i - 1)
          if fade_y > 0 and fade_y <= height then
            vim.api.nvim_buf_set_extmark(buf, ns, fade_y - 1, byte_at[fade_y][s.x], {
              end_col = byte_at[fade_y][s.x + 1],
              hl_group = "MatrixModalFade" .. i,
            })
          end
        end
      end

      if decrypt then
        for ty, row_map in pairs(decrypt.target) do
          for tx, _ in pairs(row_map) do
            vim.api.nvim_buf_set_extmark(buf, ns, ty - 1, byte_at[ty][tx], {
              end_col = byte_at[ty][tx + 1],
              hl_group = "MatrixDecryptText",
              priority = 200,
            })
          end
        end

        if decrypt.locked_count >= decrypt.target_count then
          local now2 = vim.uv.hrtime() / 1e6
          decrypt.reveal_complete_ms = decrypt.reveal_complete_ms or now2
          if decrypt.hold_duration and (now2 - decrypt.reveal_complete_ms) >= decrypt.hold_duration then
            vim.schedule(function()
              M.stop()
            end)
          end
        end
      end
    end)
  )

  vim.keymap.set("n", "q", M.stop, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", M.stop, { buffer = buf, silent = true })
end

function M.start()
  _start_modal({})
end

function M.stop()
  stop_timer()
  pcall(vim.api.nvim_clear_autocmds, { group = "MatrixModalResize" })
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  -- Drop the handles so toggle()/start() guards and a pending scheduled tick
  -- (guarded above) see a clean "no modal" state instead of stale handles.
  win = nil
  buf = nil
end

function M.toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    M.stop()
  else
    M.start()
  end
end

---@param text string Message to decrypt into the modal.
---@param opts_override? { reveal_duration?: integer, hold_duration?: integer, font?: "normal"|"block" }
function M.say(text, opts_override)
  opts_override = opts_override or {}
  M.stop()
  _start_modal({
    decrypt = {
      text = text or "",
      block = (opts_override.font or config.font) == "block",
      reveal_duration = opts_override.reveal_duration or config.reveal_duration,
      hold_duration = opts_override.hold_duration or config.hold_duration,
    },
  })
end

return M
