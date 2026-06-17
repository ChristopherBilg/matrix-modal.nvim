local M = {}

local EXPECTED_FNS = { "setup", "start", "stop", "toggle", "say", "get_theme", "health_info" }
local COMMANDS = { "Matrix", "MatrixStop", "MatrixToggle", "MatrixSay" }
local BASE_HL = { "MatrixModalBase", "MatrixDecryptText" }

local function hl_defined(name)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  return hl and next(hl) ~= nil, hl
end

local function is_num(v)
  return type(v) == "number"
end

function M.check()
  local h = vim.health
  if not h then
    print("matrix-modal: vim.health unavailable; requires Neovim 0.10+")
    return
  end

  -- Environment --------------------------------------------------------------
  h.start("matrix-modal: environment")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Requires Neovim 0.10+ (uses vim.uv and the modern highlight API)")
  end

  if vim.uv and vim.uv.new_timer then
    h.ok("vim.uv.new_timer available")
  else
    h.error("vim.uv.new_timer not available; the animation timer cannot run")
  end

  if vim.api.nvim_open_win and vim.api.nvim_buf_set_extmark then
    h.ok("floating-window and extmark APIs available")
  else
    h.error("required rendering APIs (nvim_open_win / nvim_buf_set_extmark) are missing")
  end

  -- Plugin wiring ------------------------------------------------------------
  h.start("matrix-modal: plugin")

  if vim.g.loaded_matrix_modal then
    h.ok("plugin/matrix-modal.lua has loaded")
  else
    h.warn("plugin/matrix-modal.lua has not run; user commands will be unavailable")
  end

  for _, cmd in ipairs(COMMANDS) do
    if vim.fn.exists(":" .. cmd) == 2 then
      h.ok(":" .. cmd .. " registered")
    else
      h.warn(":" .. cmd .. " not registered")
    end
  end

  -- Module integrity ---------------------------------------------------------
  h.start("matrix-modal: module")

  local ok_mod, mod = pcall(require, "matrix-modal")
  if not ok_mod or type(mod) ~= "table" then
    h.error("require('matrix-modal') failed: " .. tostring(mod))
    return
  end
  h.ok("require('matrix-modal') loaded")

  local missing = {}
  for _, fn in ipairs(EXPECTED_FNS) do
    if type(mod[fn]) ~= "function" then
      missing[#missing + 1] = fn
    end
  end
  if #missing == 0 then
    h.ok("public API complete (" .. table.concat(EXPECTED_FNS, ", ") .. ")")
  else
    h.error("missing public functions: " .. table.concat(missing, ", "))
  end

  -- Configuration ------------------------------------------------------------
  h.start("matrix-modal: configuration")

  local ok_grp, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "MatrixModalHighlights" })
  local setup_called = ok_grp and #autocmds > 0
  if setup_called then
    h.ok("setup() has been called")
  else
    h.warn("setup() has not been called; highlights will not survive a :colorscheme switch")
  end

  if type(mod.health_info) ~= "function" then
    h.warn("health_info() unavailable; skipping config and highlight validation")
    return
  end
  local info = mod.health_info()

  if vim.tbl_contains(info.themes, info.theme) then
    h.ok("theme: " .. tostring(info.theme))
  else
    h.warn(("theme %q is not a known theme (%s)"):format(tostring(info.theme), table.concat(info.themes, ", ")))
  end

  if is_num(info.charset_size) and info.charset_size > 0 then
    local label = type(info.chars) == "string" and (" (" .. info.chars .. ")") or ""
    h.ok(("charset: %d glyphs%s"):format(info.charset_size, label))
  else
    h.error("resolved charset is empty; there are no characters to render")
  end

  if is_num(info.density) and info.density >= 0 and info.density <= 1 then
    h.ok(("density: %.3g (per-column spawn chance per frame)"):format(info.density))
  else
    h.warn("density should be a number in [0.0, 1.0]; got " .. tostring(info.density))
  end

  if is_num(info.speed) and info.speed > 0 then
    h.ok(("speed: %s ms/frame"):format(tostring(info.speed)))
  else
    h.warn("speed should be a positive number (ms per frame); got " .. tostring(info.speed))
  end

  for _, dim in ipairs({ "width", "height" }) do
    local v = info[dim]
    if is_num(v) and v > 0 then
      h.ok(("%s: %s"):format(dim, tostring(v)))
    else
      h.warn(("%s should be a positive number (fraction <1 or absolute >=1); got %s"):format(dim, tostring(v)))
    end
  end

  if is_num(info.reveal_duration) and info.reveal_duration >= 1 then
    h.ok(("reveal_duration: %s ms"):format(tostring(info.reveal_duration)))
  else
    h.warn("reveal_duration should be >= 1 ms; got " .. tostring(info.reveal_duration))
  end

  if info.hold_duration == nil then
    h.info("hold_duration: nil (revealed messages persist until dismissed)")
  elseif is_num(info.hold_duration) and info.hold_duration > 0 then
    h.ok(("hold_duration: %s ms"):format(tostring(info.hold_duration)))
  else
    h.warn("hold_duration should be nil or a positive number; got " .. tostring(info.hold_duration))
  end

  if is_num(info.text_padding) and info.text_padding >= 0 and info.text_padding == math.floor(info.text_padding) then
    h.ok(("text_padding: %d cell(s) of rain-free margin around text"):format(info.text_padding))
  else
    h.warn("text_padding should be an integer >= 0; got " .. tostring(info.text_padding))
  end

  if info.font == "normal" or info.font == "block" then
    h.ok(("font: %s"):format(info.font))
  else
    h.warn(('font should be "normal" or "block"; got %s'):format(tostring(info.font)))
  end

  local fade_count = type(info.fade_colors) == "table" and #info.fade_colors or 0
  if fade_count > 0 then
    h.ok(("fade gradient: %d levels"):format(fade_count))
  else
    h.warn("fade_colors is empty; the rain will have no trailing gradient")
  end

  -- Highlights ---------------------------------------------------------------
  h.start("matrix-modal: highlights")

  local hint = setup_called and "" or " (call setup())"
  for _, name in ipairs(BASE_HL) do
    local defined, hl = hl_defined(name)
    if defined then
      h.ok(("%s defined (fg=0x%06X)"):format(name, hl.fg or 0))
    else
      h.warn(name .. " is not defined" .. hint)
    end
  end

  if fade_count > 0 then
    local fade_missing = {}
    for i = 1, fade_count do
      if not hl_defined("MatrixModalFade" .. i) then
        fade_missing[#fade_missing + 1] = "MatrixModalFade" .. i
      end
    end
    if #fade_missing == 0 then
      h.ok(("%d/%d fade highlight groups defined"):format(fade_count, fade_count))
    else
      h.warn(
        ("%d/%d fade highlight groups missing: %s"):format(#fade_missing, fade_count, table.concat(fade_missing, ", "))
          .. hint
      )
    end
  end
end

return M
