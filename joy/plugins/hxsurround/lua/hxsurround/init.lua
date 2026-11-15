-- hxsurround: the actions behind m S, m D and m R (see plugin/hxsurround.lua),
-- and setup(). Each action edits the buffer with one call, so one u undoes
-- it, then selects what it made, in normal mode, as Helix does.
local wrap = require("hxsurround.wrap")
local find = require("hxsurround.find")

local M = {}

---@alias hxsurround.Surround [string, string]|fun(sel: joy.Selection?): string?, string?

---@class hxsurround.Config
---@field surrounds table<string, hxsurround.Surround> Keys of m S and m D: { open, close } or a function of the selection giving them.
M.config = { surrounds = {} }

-- The buffer and its selection ------------------------------------------

---@class hxsurround.Ctx
---@field lines string[]
---@field text string The lines joined by "\n".
---@field s integer The selection's start, a 0-based byte offset.
---@field e integer Past its end.
---@field sel joy.Selection? The selection; nil when nothing is selected.
---@field srow integer Its first line, 1-based.
---@field erow integer Its last line, 1-based.
---@field linewise boolean It is whole lines (as x selects).

-- offset is the 0-based byte offset of {row (1-based), col}.
local function offset(lines, row, col)
  local off = 0
  for i = 1, math.min(row - 1, #lines) do off = off + #lines[i] + 1 end
  return off + col
end

-- position is the 0-based {row, col} of an offset.
local function position(text, off)
  local row, start = 0, 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl or nl > off then break end
    row, start = row + 1, nl + 1
  end
  return row, off - (start - 1)
end

---@return hxsurround.Ctx
local function context()
  local lines = joy.buffer.get_lines(0, 0, -1) or {}
  local text = table.concat(lines, "\n")
  local sel = joy.buffer.get_selection(0)
  local sr, sc, er, ec
  if sel and sel.text ~= "" then
    sr, sc, er, ec = sel.row + 1, sel.col, sel.end_row + 1, sel.end_col
  else -- nothing selected: the character under the cursor, the newline past a line's end
    sel = nil
    local c = joy.buffer.get(0).cursor
    local ch = (lines[c.row + 1] or ""):sub(c.col + 1):match("^[%z\1-\127\194-\244][\128-\191]*") or "\n"
    sr, sc, er, ec = c.row + 1, c.col, c.row + 1, c.col + #ch
  end
  local linewise = sc == 0 and ec == 0 and er > sr
  local s = offset(lines, sr, sc)
  local e = math.min(offset(lines, er, ec), #text)
  return { lines = lines, text = text, s = s, e = math.max(e, s), sel = sel, srow = sr,
    erow = linewise and er - 1 or er, linewise = linewise }
end

-- select selects n bytes from offset off of the text as it is now: Helix's
-- primary selection. Whole lines end at the start of the row after them.
-- As Helix's surround, it ends in normal mode: esc leaves select mode and
-- keeps the selection.
local function select(off, n)
  local text = joy.buffer.get_text(0) or ""
  local row, col = position(text, off)
  local end_row, end_col = position(text, off + n)
  joy.buffer.set_selection(0, { row = row, col = col, end_row = end_row, end_col = end_col })
  local b = joy.buffer.get(0)
  if b and b.mode == "select" then joy.editor.feed_keys("esc", { skip_keymaps = true }) end
end

-- replace puts new in place of [s, e) of the text, with one call.
local function replace(ctx, s, e, new)
  local sr, sc = position(ctx.text, s)
  local er, ec = position(ctx.text, e)
  joy.buffer.edit(0, { { row = sr, col = sc, end_row = er, end_col = ec, text = new } })
end

-- set_lines replaces lines first..last (1-based) with new, and selects them.
local function set_lines(ctx, first, last, new)
  joy.buffer.set_lines(0, first - 1, last, new)
  if #new > 0 then select(offset(ctx.lines, first, 0), #table.concat(new, "\n") + 1) end
end

local function notify(msg)
  joy.ui.notify(msg, { level = "warning", title = "hxsurround" })
end

-- ask asks for a line of text: what was typed, or nil for nothing or esc.
-- Keymaps run as tasks, so the prompt just waits.
local function ask(prompt, default)
  local input = joy.ui.input(prompt, { default = default })
  if input and input ~= "" then return input end
end

-- The user's surround of a key, as open and close.
local function user(key, ctx)
  local u = M.config.surrounds[key]
  if type(u) == "function" then return u(ctx.sel) end
  if type(u) == "table" then return u[1], u[2] end
end

-- m S --------------------------------------------------------------------

-- wrap_with wraps the selection: a tag or a fence (kind "tag", "fence") of
-- whole lines as a block, the rest in its line(s).
local function wrap_with(ctx, open, close, kind)
  local multi = ctx.erow > ctx.srow
  if kind == "fence" and multi or kind == "tag" and ctx.linewise then
    local lines = { unpack(ctx.lines, ctx.srow, ctx.erow) }
    return set_lines(ctx, ctx.srow, ctx.erow, wrap.block(lines, open, close, kind == "tag" and wrap.unit() or ""))
  end
  local s, e = ctx.s, ctx.e
  if ctx.linewise then -- whole lines: from the first non-blank to the last line's end
    s = s + #ctx.lines[ctx.srow]:match("^%s*")
    e = offset(ctx.lines, ctx.erow, #ctx.lines[ctx.erow])
  end
  local new = open .. ctx.text:sub(s + 1, e) .. close
  replace(ctx, s, e, new)
  select(s, #new)
end

--- Wraps the primary selection with the surround of `key`.
---@param key string
function M.add(key)
  local ctx = context()
  if M.config.surrounds[key] then
    local open, close = user(key, ctx)
    if open then wrap_with(ctx, open, close or open) end
  elseif key == "t" then
    local input = ask("Tag: ", "")
    if not input then return end
    local open, close = wrap.tag(input)
    if open then wrap_with(ctx, open, close, "tag") end
  elseif key == "f" then
    local name = ask("Function: ", "")
    if name then wrap_with(ctx, name .. "(", ")") end
  elseif key == "c" then
    local open = ask("Open: ", "")
    if open then wrap_with(ctx, open, wrap.close_of(open)) end
  elseif key == "`" and ctx.erow > ctx.srow then
    wrap_with(ctx, "```" .. joy.buffer.get(0).language, "```", "fence")
  elseif wrap.markdown[key] or wrap.pairs[key] then
    local p = wrap.markdown[key] or wrap.pairs[key]
    wrap_with(ctx, p[1], p[2])
  end
end

-- m D --------------------------------------------------------------------

-- unwrap deletes a match's open and close, keeping what is between. A tag
-- on lines of its own goes with its lines, the lines between dedented.
local function unwrap(ctx, m, what)
  if not m then return notify("no " .. what .. " around the selection") end
  local orow, ocol = position(ctx.text, m.os)
  local crow, ccol = position(ctx.text, m.cs)
  local oline, cline = ctx.lines[orow + 1], ctx.lines[crow + 1]
  if what == "tag" and orow < crow and oline:sub(1, ocol):find("^%s*$") and oline:sub(m.oe - m.os + ocol + 1):find("^%s*$")
      and cline:sub(1, ccol):find("^%s*$") and cline:sub(m.ce - m.cs + ccol + 1):find("^%s*$") then
    local inner = wrap.dedent({ unpack(ctx.lines, orow + 2, crow) }, wrap.unit())
    return set_lines(ctx, orow + 1, crow + 1, inner)
  end
  local inner = ctx.text:sub(m.oe + 1, m.cs)
  replace(ctx, m.os, m.ce, inner)
  select(m.os, #inner)
end

--- Deletes the nearest surround of `key` around the primary selection.
---@param key string
function M.delete(key)
  local ctx = context()
  local s, e, text = ctx.s, ctx.e, ctx.text
  if M.config.surrounds[key] then
    local open, close = user(key, ctx)
    if open then unwrap(ctx, find.pair(text, s, e, open, close or open), open .. "…" .. (close or open)) end
  elseif key == "t" then
    unwrap(ctx, find.tag(text, s, e), "tag")
  elseif key == "f" then
    unwrap(ctx, find.call(text, s, e), "function call")
  elseif key == "c" then
    local open = ask("Delete open: ", "")
    if not open then return end
    local close = wrap.close_of(open)
    unwrap(ctx, find.pair(text, s, e, open, close), open .. "…" .. close)
  elseif key == "*" then
    unwrap(ctx, find.marker(text, s, e, "**") or find.marker(text, s, e, "*"), "**")
  elseif key == "`" then
    local m = find.marker(text, s, e, "`")
    if m then return unwrap(ctx, m, "`") end
    local first, last = find.fence(ctx.lines, ctx.srow)
    if not first then return notify("no ` or ``` block around the selection") end
    set_lines(ctx, first, last, { unpack(ctx.lines, first + 1, last - 1) })
  elseif wrap.markdown[key] then
    unwrap(ctx, find.marker(text, s, e, wrap.markdown[key][1]), wrap.markdown[key][1])
  end
end

-- m R --------------------------------------------------------------------

--- Changes the nearest tag (t: its name, its attributes kept unless new
--- ones are typed) or function call (f: its name) around the selection.
---@param key string
function M.change(key)
  local ctx = context()
  if key == "t" then
    local m = find.tag(ctx.text, ctx.s, ctx.e)
    if not m then return notify("no tag around the selection") end
    local input = ask("Tag: ", m.name)
    if not input then return end
    local open, close, name = wrap.tag(input)
    if not open or not name then return end
    if not input:find("%s") then open = "<" .. name .. m.attrs .. ">" end
    local new = open .. ctx.text:sub(m.oe + 1, m.cs) .. close
    replace(ctx, m.os, m.ce, new)
    select(m.os, #new)
  elseif key == "f" then
    local m = find.call(ctx.text, ctx.s, ctx.e)
    if not m then return notify("no function call around the selection") end
    local name = ask("Function: ", m.name)
    if not name then return end
    replace(ctx, m.os, m.oe - 1, name)
    select(m.os, #(name .. ctx.text:sub(m.oe, m.ce)))
  end
end

-- setup ------------------------------------------------------------------

--- Optional. `surrounds` adds keys to m S and m D (or changes built-in
--- ones): `{ x = { "open", "close" } }`, or a function of the selection
--- (`joy.buffer.get_selection(0)`, nil when nothing is selected) returning
--- open and close.
---@param opts? { surrounds?: table<string, hxsurround.Surround> }
function M.setup(opts)
  for key, s in pairs(opts and opts.surrounds or {}) do
    M.config.surrounds[key] = s
    local id, what = "user-" .. key:byte(), key
    if type(s) == "table" then what = s[1] .. "…" .. (s[2] or s[1]) end
    joy.keymap.set("wrap-" .. id, "m S " .. key, function() M.add(key) end,
      { when = "normal select", desc = "Wrap in " .. what })
    joy.keymap.set("delete-" .. id, "m D " .. key, function() M.delete(key) end,
      { when = "normal select", desc = "Delete the " .. what .. " around" })
  end
end

return M
