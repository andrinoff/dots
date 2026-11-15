-- The actions loam's keymaps run, as oil's: `actions.select` and so on.
-- Each takes the keymap's `opts`.

local config = require("loam.config")
local fs = require("loam.fs")
local view = require("loam.view")

local M = {}

M.descriptions = {
  select = "Open the entry: a file, or the directory in loam",
  parent = "Go to the parent directory",
  open_cwd = "Open the current directory",
  cd = "cd to the directory",
  change_sort = "Change the sort order",
  open_external = "Open the entry with the system's app",
  toggle_hidden = "Show or hide hidden files",
  preview = "Preview the entry in a split",
  close = "Close loam",
  refresh = "List the directory again",
  show_help = "Show loam's keys",
}

---@param buf? integer
---@return loam.BufState?
local function state(buf)
  buf = buf or view.current()
  return buf and view.bufs[buf]
end

--- The window a "float" was opened from, when the current window is one.
---@return integer?
local function float_origin()
  local origin = view.origins[joy.editor.get().window]
  if origin and joy.window.get(origin) then
    return origin
  end
  return nil
end

--- Opens the entry under the cursor. opts: vertical, horizontal (splits)
--- or tab (joy has one tab page: a new buffer of the bufferline, as
--- without it).
---@param opts? {vertical?: boolean, horizontal?: boolean, tab?: boolean}
function M.select(opts)
  opts = opts or {}
  local loam = require("loam")
  local buf = view.current()
  local st = state(buf)
  local line = view.cursor_line(buf)
  if not st or not line then
    return
  end
  local path, is_dir
  local e = line.entry
  if e and e.dir == st.dir and line.name == e.name then
    path, is_dir = fs.join(e.dir, e.name), view.dir_like(e)
  else
    -- A new, renamed or pasted line: what it names is made by saving.
    if not config.options.prompt_save_on_select_new_entry then
      joy.ui.notify("loam: save first: " .. line.name .. " isn't there yet", { level = "warning" })
      return
    end
    local name = line.name
    if not loam.save() then
      return
    end
    path = fs.join(st.dir, name)
    is_dir = fs.is_dir(path)
    if not fs.exists(path) then
      return
    end
  end
  if is_dir then
    if opts.vertical or opts.horizontal then
      loam.open(path, { split = opts.vertical and "vertical" or "horizontal" })
    else
      loam.open(path)
    end
    return
  end
  local origin = float_origin()
  if origin then
    joy.window.close(0)
    joy.window.focus(origin)
  end
  if opts.vertical then
    joy.window.split(0, { vertical = true, path = path })
  elseif opts.horizontal then
    joy.window.split(0, { path = path })
  else
    joy.buffer.open(path)
  end
end

--- The parent directory, the cursor on the one left.
function M.parent()
  local st = state()
  if not st then
    return require("loam").open()
  end
  if st.dir == "/" then
    return
  end
  require("loam").open(fs.parent(st.dir), { focus = fs.basename(st.dir) })
end

--- The current directory.
function M.open_cwd()
  require("loam").open(joy.editor.get().cwd)
end

--- Makes the buffer's directory joy's working directory. (joy has one
--- directory: `scope = "tab"` changes it too.)
function M.cd()
  local st = state()
  if not st then
    return
  end
  joy.editor.set_cwd(st.dir)
  joy.ui.notify("cd " .. st.dir)
end

--- Asks for a column and an order to sort by.
function M.change_sort()
  local _, col = joy.ui.pick({ "name", "type", "size", "mtime" }, { title = "Sort by" })
  if not col then
    return
  end
  local _, order = joy.ui.pick({ "asc", "desc" }, { title = "Sort order" })
  if not order then
    return
  end
  local sort
  if col == "type" then
    sort = { { "type", order }, { "name", "asc" } }
  else
    sort = { { "type", "asc" }, { col, order } }
  end
  require("loam").set_sort(sort)
end

--- Opens the entry with the system's app (joy.process.open: `open` on
--- macOS, `xdg-open` elsewhere), or config.open_cmd.
function M.open_external()
  local path = require("loam").get_cursor_path()
  if not path then
    return
  end
  local cmd = config.options.open_cmd
  if type(cmd) == "function" then
    return cmd(path)
  end
  if type(cmd) ~= "table" then
    local ok, err = joy.process.open(path) -- the system's opener
    if not ok then
      joy.ui.notify("loam: " .. tostring(err), { level = "error" })
    end
    return
  end
  local argv = {}
  for i, a in ipairs(cmd) do
    argv[i] = a
  end
  argv[#argv + 1] = path
  joy.process.start(argv, { detach = true })
end

function M.toggle_hidden()
  require("loam").toggle_hidden()
end

---@type integer?
M.preview_win = nil
---@type string?
M.preview_path = nil
---@type integer?
local preview_buf = nil

--- The preview's lines of a file: its first lines, unless it is binary.
---@param path string
---@return string[]
local function file_lines(path)
  local data, err = joy.fs.read(path)
  if not data then
    return { "(" .. tostring(err) .. ")" }
  end
  if data:find("\0", 1, true) then
    return { "(binary file, " .. #data .. " bytes)" }
  end
  local lines = {}
  -- (joy's Lua crashes on "for x in (f() .. s):gmatch(p)": a local first.)
  local text = data:gsub("\r\n", "\n") .. "\n"
  for line in text:gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
    if #lines >= 2000 then
      break
    end
  end
  if lines[#lines] == "" and #lines > 1 then
    lines[#lines] = nil
  end
  return lines
end

--- Puts path in the preview's buffer, made the first time: a file's
--- lines, or a directory's names. It is a scratch buffer of its own:
--- opening the file there would take it from a window that has it open.
---@param path string
---@return integer buf
local function fill_preview(path)
  M.preview_path = path
  local lines
  local language = ""
  if fs.is_dir(path) then
    lines = {}
    for _, fe in ipairs(fs.list(path) or {}) do
      lines[#lines + 1] = fe.name .. (fe.type == "directory" and "/" or "")
    end
    table.sort(lines)
  else
    lines = file_lines(path)
    language = joy.editor.detect_language(path)
  end
  lines = #lines > 0 and lines or { "" }
  if not preview_buf or not joy.buffer.get(preview_buf) then
    preview_buf = joy.buffer.create({ lines = lines, unlisted = true })
  else
    joy.buffer.set_lines(preview_buf, 0, -1, lines)
  end
  -- Plain text for a language joy has no grammar of.
  if not pcall(joy.buffer.set_language, preview_buf, language) then
    joy.buffer.set_language(preview_buf, "")
  end
  return preview_buf
end

--- Shows path in the preview window.
---@param path string
local function show_preview(path)
  local win = M.preview_win and joy.window.get(M.preview_win)
  if not win then
    return
  end
  local buf = fill_preview(path)
  if win.buffer ~= buf then
    joy.window.set_buffer(win.id, buf)
  end
end

--- Opens (or closes) a split showing the entry under the cursor, which
--- follows the cursor.
function M.preview()
  if M.preview_win and joy.window.get(M.preview_win) then
    if preview_buf and joy.buffer.get(preview_buf) then
      joy.buffer.close(preview_buf, { force = true })
    end
    preview_buf = nil
    joy.window.close(M.preview_win)
    M.preview_win, M.preview_path = nil, nil
    return
  end
  local path = require("loam").get_cursor_path()
  if not path or not fs.exists(path) then
    return
  end
  M.preview_win = joy.window.split(0, { vertical = true, keep_focus = true, buffer = fill_preview(path) })
end

--- Follows the cursor with the preview, when one is open.
---@param buf integer
function M.update_preview(buf)
  if not M.preview_win or not joy.window.get(M.preview_win) or view.current() ~= buf then
    return
  end
  local path = require("loam").get_cursor_path()
  if path and path ~= M.preview_path and fs.exists(path) then
    show_preview(path)
  end
end

--- Forgets the preview when its window closed, closing its buffer.
---@param win integer
function M.window_closed(win)
  if win ~= M.preview_win then
    return
  end
  if preview_buf then
    joy.buffer.close(preview_buf, { force = true })
  end
  preview_buf, M.preview_win, M.preview_path = nil, nil, nil
end

function M.close()
  require("loam").close()
end

--- Lists the directory again, asking first when there are edits.
function M.refresh()
  local b = joy.buffer.get(0)
  if not b or not state(b.id) then
    return
  end
  if b.modified and not joy.ui.confirm("Discard changes?") then
    return
  end
  view.render(b.id)
end

--- The keys of a loam buffer, in a panel (q or esc closes it).
function M.show_help()
  local lines = { "loam: keys in this buffer", "" }
  for _, k in ipairs(require("loam.keymaps").list()) do
    lines[#lines + 1] = string.format("  %-8s %s", k[1], k[2])
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  :w applies the edits; q or esc closes this"
  joy.ui.panel("help", lines, {
    title = "loam",
    on_key = function(key)
      if key == "q" or key == "esc" or key == "g" or key == "?" then
        joy.ui.close("help")
      end
    end,
  })
end

return M
