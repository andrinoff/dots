-- loam's buffers: the entries and their ids, rendering a directory into a
-- buffer, parsing its lines back, and the decorations that hide the ids.
--
-- Each line is an entry's name followed by its id, "name ::007". The id is
-- part of the text, so it goes wherever the line goes: yanked and pasted,
-- cut into another loam buffer, undone. Virtual text hides it, and shows
-- the other columns in its place; it sits at the end of the line, so that
-- nothing of the line is drawn after it.

local config = require("loam.config")
local fs = require("loam.fs")
local icons = require("loam.icons")

local M = {}

---@class loam.Entry
---@field id integer
---@field dir string The directory it was listed in.
---@field name string
---@field type string "file", "directory", "link"...
---@field link? string A link's target.
---@field link_type? string What a link points to.
---@field mode? integer
---@field size? integer
---@field mtime? number

---@class loam.BufState
---@field dir string
---@field ids integer[] The ids rendered, in order.
---@field lines string[] The lines rendered.

---@class loam.Line
---@field id? integer An entry's id, when the line has a known one.
---@field entry? loam.Entry
---@field name string The name typed, without its trailing "/" or a link's " -> target".
---@field is_dir boolean
---@field link? string The target of a new link, "name -> target".
---@field row integer 1-based.

---@type table<integer, loam.Entry>
M.entries = {}
---@type table<string, integer>
M.by_path = {}
M.next_id = 1
---@type table<integer, loam.BufState>
M.bufs = {}
---@type table<string, integer>
M.dir_bufs = {}

-- Windows by id, forgotten as they close: a "float"'s window → the window
-- it was opened from, and a window loam took → the buffer it showed before.
---@type table<integer, integer>
M.origins = {}
---@type table<integer, integer>
M.previous = {}

--- The current buffer's id; nil with no editor window.
---@return integer?
function M.current()
  local b = joy.buffer.get(0)
  return b and b.id
end

-- The suffix holding an id: two colons and three digits or more, after
-- optional blanks, at the end of the line.
local SUFFIX = "%s*::(%d%d%d+)%s*$"

--- Splits a line into its text and the id at its end: the text, the id
--- (a number, nil for none) and the byte where the id's suffix starts
--- (0-based).
---@param line string
---@return string text
---@return integer? id
---@return integer? at
function M.split_line(line)
  local s, _, id = line:find(SUFFIX)
  if s then
    return line:sub(1, s - 1), tonumber(id), s - 1
  end
  return line, nil, nil
end

---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Reads a line: nil for a blank one.
---@param line string
---@param row integer
---@return loam.Line?
function M.parse_line(line, row)
  local text, id = M.split_line(line)
  text = trim(text)
  local e = id and M.entries[id] or nil
  if text == "" and not e then
    return nil
  end
  if e then
    local name = text
    if e.type == "link" then
      name = name:gsub(" %-> .*$", "")
    end
    name = name:gsub("/+$", "")
    return { id = e.id, entry = e, name = name, is_dir = e.type == "directory", row = row }
  end
  local name, target = text:match("^(.-) %-> (.+)$")
  if name then
    return { name = trim(name):gsub("/+$", ""), link = target, is_dir = false, row = row }
  end
  return { name = (text:gsub("/+$", "")), is_dir = text:sub(-1) == "/", row = row }
end

--- The id of the entry at a path, made the first time.
---@param dir string
---@param fe loam.FsEntry
---@return loam.Entry
function M.entry_for(dir, fe)
  local path = fs.join(dir, fe.name)
  local id = M.by_path[path]
  local e = id and M.entries[id]
  if not e then
    id = M.next_id
    M.next_id = M.next_id + 1
    e = { id = id, dir = dir, name = fe.name, type = fe.type }
    M.entries[id] = e
    M.by_path[path] = id
  end
  e.type, e.link, e.link_type = fe.type, fe.link, fe.link_type
  e.mode, e.size, e.mtime = fe.mode, fe.size, fe.mtime
  return e
end

--- Whether an entry is a directory or a link to one.
---@param e loam.Entry
---@return boolean
function M.dir_like(e)
  return e.type == "directory" or (e.type == "link" and e.link_type == "directory")
end

---@param e loam.Entry
---@return boolean
local function visible(e)
  local view = config.options.view_options
  if view.is_always_hidden(e.name, e) then
    return false
  end
  return view.show_hidden or not view.is_hidden_file(e.name, e)
end

-- natural splits a name into its runs of digits and of other characters,
-- for comparing "a2" before "a10".
---@param s string
---@return (string|number)[]
local function chunks(s)
  local out = {}
  for digits, other in s:gmatch("(%d*)(%D*)") do
    if digits ~= "" then
      out[#out + 1] = tonumber(digits) or digits
    end
    if other ~= "" then
      out[#out + 1] = other
    end
  end
  return out
end

---@param a string
---@param b string
---@return integer -1, 0 or 1
local function compare_names(a, b)
  local view = config.options.view_options
  if view.case_insensitive then
    a, b = a:lower(), b:lower()
  end
  if not view.natural_order then
    return a < b and -1 or (a > b and 1 or 0)
  end
  local ca, cb = chunks(a), chunks(b)
  for i = 1, math.max(#ca, #cb) do
    local x, y = ca[i], cb[i]
    if x == nil then
      return -1
    end
    if y == nil then
      return 1
    end
    if x ~= y then
      if type(x) == type(y) then
        return x < y and -1 or 1
      end
      return type(x) == "number" and -1 or 1
    end
  end
  return 0
end

local function type_rank(e)
  if M.dir_like(e) then
    return 1
  end
  return 2
end

---@param a loam.Entry
---@param b loam.Entry
---@return boolean
local function less(a, b)
  for _, spec in ipairs(config.options.view_options.sort) do
    local key, order = spec[1], spec[2]
    local c = 0
    if key == "type" then
      local x, y = type_rank(a), type_rank(b)
      c = x < y and -1 or (x > y and 1 or 0)
    elseif key == "name" then
      c = compare_names(a.name, b.name)
    elseif key == "size" then
      local x, y = a.size or 0, b.size or 0
      c = x < y and -1 or (x > y and 1 or 0)
    elseif key == "mtime" then
      local x, y = a.mtime or 0, b.mtime or 0
      c = x < y and -1 or (x > y and 1 or 0)
    end
    if c ~= 0 then
      if order == "desc" then
        return c > 0
      end
      return c < 0
    end
  end
  return a.name < b.name
end

--- A line of an entry: "name/ ::007".
---@param e loam.Entry
---@return string
function M.format(e)
  local text = e.name
  if e.type == "directory" then
    text = text .. "/"
  elseif e.type == "link" then
    text = text .. " -> " .. (e.link or "?")
  end
  return text .. string.format(" ::%03d", e.id)
end

--- The cache file a loam buffer has as its file, which `:w` writes; the
--- buffer_saved that follows applies the changes. (joy has no buffers
--- without files that `:w` writes.) Its name is the directory's, with %
--- for each /.
---@param dir string
---@return string
function M.cache_path(dir)
  local base = fs.join(joy.editor.get().dirs.cache, "loam")
  local home = os.getenv("HOME")
  local name = dir
  if home and home ~= "/" and fs.is_under(dir, home) then
    name = "~" .. dir:sub(#home + 1) -- "~%work%x", as joy shows it, shorter
  end
  return fs.join(base, (name:gsub("/", "%%")))
end

--- Puts the cursor on the entry named `name`.
---@param buf integer
---@param name string
---@return boolean found
function M.focus(buf, name)
  for i, line in ipairs(joy.buffer.get_lines(buf, 0, -1) or {}) do
    local p = M.parse_line(line, i)
    if p and p.name == name then
      joy.buffer.set_cursor(buf, { row = i - 1, col = 0 })
      return true
    end
  end
  return false
end

--- The entry line under the cursor.
---@param buf? integer
---@return loam.Line?
function M.cursor_line(buf)
  local b = joy.buffer.get(buf or 0)
  if not b then
    return nil
  end
  local c = b.cursor
  local line = (joy.buffer.get_lines(b.id, c.row, c.row + 1) or {})[1]
  if not line then
    return nil
  end
  return M.parse_line(line, c.row + 1)
end

--- Lists the buffer's directory into it, as unmodified; the cursor goes on
--- `focus`, or stays on its entry (false: neither).
---@param buf integer
---@param focus? string|false
function M.render(buf, focus)
  local st = M.bufs[buf]
  if not st then
    return
  end
  if focus == nil then
    local cur = M.cursor_line(buf)
    focus = cur and cur.name or nil
  end
  local list, err = fs.list(st.dir)
  if not list then
    joy.ui.notify("loam: " .. tostring(err), { level = "error" })
    list = {}
  end
  local shown = {}
  for _, fe in ipairs(list) do
    local e = M.entry_for(st.dir, fe)
    if visible(e) then
      shown[#shown + 1] = e
    end
  end
  table.sort(shown, less)
  local lines, ids = {}, {}
  for i, e in ipairs(shown) do
    lines[i] = M.format(e)
    ids[i] = e.id
  end
  joy.buffer.set_lines(buf, 0, -1, lines)
  joy.buffer.set_modified(buf, false)
  st.ids, st.lines = ids, lines
  M.decorate(buf)
  if focus then
    M.focus(buf, focus)
  end
end

-- The text a column shows for an entry.
---@param col string|table
---@param e loam.Entry
---@return string
local function column_text(col, e)
  local name = type(col) == "table" and col[1] or col
  if name == "permissions" then
    return fs.permissions(e.type, e.mode)
  elseif name == "size" then
    local s = M.dir_like(e) and "-" or fs.human_size(e.size)
    return string.rep(" ", math.max(5 - #s, 0)) .. s
  elseif name == "mtime" then
    local fmt = type(col) == "table" and col.format or "%b %d %H:%M"
    return e.mtime and tostring(os.date(fmt, math.floor(e.mtime))) or "-"
  end
  return ""
end

--- Draws what isn't text: virtual text in place of each id (with the
--- columns), the icons as signs, and the colors of directories and links.
--- Decorations stay where they were put, so this runs again after each
--- change.
---@param buf integer
function M.decorate(buf)
  local lines = M.bufs[buf] and joy.buffer.get_lines(buf, 0, -1)
  if not lines then
    return
  end
  local want_icon, cols = false, {}
  for _, c in ipairs(config.options.columns) do
    local name = type(c) == "table" and c[1] or c
    if name == "icon" then
      want_icon = true
    else
      cols[#cols + 1] = c
    end
  end
  local split, width = {}, 0
  for i, line in ipairs(lines) do
    local text, id, at = M.split_line(line)
    split[i] = { text = text, id = id, at = at }
    if id and M.entries[id] then
      width = math.max(width, joy.util.width(text))
    end
  end
  local texts, highlights, signs = {}, {}, {}
  for i, s in ipairs(split) do
    local e = s.id and M.entries[s.id] or nil
    local typ = e and e.type or (s.text:match("/%s*$") and "directory" or "file")
    if e and s.at then
      local text = ""
      if #cols > 0 then
        local parts = {}
        for _, c in ipairs(cols) do
          parts[#parts + 1] = column_text(c, e)
        end
        text = string.rep(" ", width - joy.util.width(s.text) + 2) .. table.concat(parts, "  ")
      end
      -- In place of the id: columns shorter than it leave blank cells.
      texts[#texts + 1] = { row = i - 1, col = s.at, hide_until = #lines[i], text = text,
        style = { link = "loam-column" } }
    end
    local name_end = #s.text:gsub("%s+$", "")
    if name_end > 0 then
      local role = (typ == "directory" and "loam-dir") or (typ == "link" and "loam-link") or nil
      if role then
        highlights[#highlights + 1] = { row = i - 1, col = 0, end_row = i - 1, end_col = name_end,
          style = { link = role } }
      end
      if want_icon then
        local base = trim(s.text):gsub("/+$", "")
        signs[#signs + 1] = {
          row = i - 1,
          text = icons.get(base, e and M.dir_like(e) and "directory" or typ),
          style = { link = typ == "directory" and "loam-dir" or "loam-icon" },
        }
      end
    end
  end
  joy.buffer.decorate(buf, "loam", { virtual_text = texts, highlights = highlights, signs = signs })
end

--- Keeps the cursor off the hidden id: before it in insert mode (before a
--- directory's "/"), on the name in normal mode (unless a selection spans
--- more).
---@param buf integer
function M.constrain(buf)
  local b = joy.buffer.get(buf)
  if not config.options.constrain_cursor or not b or not b.focused then
    return
  end
  local insert, pos = b.mode == "insert", b.cursor
  local line = (joy.buffer.get_lines(buf, pos.row, pos.row + 1) or {})[1]
  if not line then
    return
  end
  local text, id, at = M.split_line(line)
  if not id or not at then
    return
  end
  local body = text:gsub("%s+$", "")
  local max = at
  if not insert then
    max = math.max(#body - 1, 0)
  elseif body:sub(-1) == "/" then
    max = #body - 1 -- a directory's name is typed before its "/"
  end
  if pos.col <= max then
    return
  end
  if not insert then
    local sel = joy.buffer.get_selection(buf)
    if sel and #sel.text > 1 then
      return
    end
  end
  joy.buffer.set_cursor(buf, { row = pos.row, col = max })
end

return M
