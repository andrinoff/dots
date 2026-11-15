-- loam: edit the file system as a buffer, as oil.nvim does, in joy.
--
--   require("loam").setup(opts)   options (lua/loam/config.lua)
--   require("loam").open(dir?)    the directory, or the current file's
--   :Loam [--float] [dir]         the same, as a command
--   -                             the parent directory of the current file
--   :w in a loam buffer           applies the edits of every loam buffer
--   :LoamSave                     the same (when apply_on_write is false)
--
-- In a loam buffer, edit the lines and :w: a new line creates (a "/" at the
-- end makes a directory, "a/b/c.txt" makes the directories on the way),
-- a removed line deletes, a changed name renames, a line cut and pasted
-- into another loam buffer moves, and a line yanked and pasted copies.

local config = require("loam.config")
local fs = require("loam.fs")
local view = require("loam.view")
local mutator = require("loam.mutator")

local M = {}

local saving = false

---@class loam.OpenOpts
---@field float? boolean Opens a window of its own (joy has no floats: a split).
---@field split? "vertical"|"horizontal" Opens it in a new split.
---@field window? integer The window to show it in; the current buffer's by default.
---@field focus? string The entry to put the cursor on.

--- Sets loam up; plugin/loam.lua calls it with no options unless the
--- config did first.
---@param opts? table
function M.setup(opts)
  config.options = config.build(opts)
  M.did_setup = true
  local icons = require("loam.icons")
  for key, glyph in pairs(config.options.icons or {}) do
    if key:find(".", 1, true) or icons.by_name[key] then
      icons.by_name[key] = glyph
    else
      icons.by_ext[key] = glyph
    end
  end
  -- Defaults: a theme or the user's init.lua may style them first.
  joy.theme.define("loam-dir", { link = "tree-dir" })
  joy.theme.define("loam-link", { link = "constant" })
  joy.theme.define("loam-icon", { link = "builtin" })
  joy.theme.define("loam-column", { link = "comment" })
  local km = require("loam.keymaps")
  km.set_global()
  for buf in pairs(view.bufs) do
    local b = joy.buffer.get(buf)
    if b then
      km.set_buffer(buf)
      if not b.modified then
        view.render(buf)
      end
    end
  end
end

--- Whether buf is a loam buffer.
---@param buf? integer
---@return boolean
function M.is_loam(buf)
  buf = buf or view.current()
  return buf ~= nil and view.bufs[buf] ~= nil and joy.buffer.get(buf) ~= nil
end

--- The directory of a loam buffer (the current one by default).
---@param buf? integer
---@return string?
function M.get_current_dir(buf)
  buf = buf or view.current()
  local st = buf and view.bufs[buf]
  return st and st.dir or nil
end

--- The entry under the cursor, as rendered: nil on a new line.
---@return loam.Entry?
function M.get_cursor_entry()
  local line = view.cursor_line()
  return line and line.entry or nil
end

--- The path under the cursor: the entry's, or what a new line names.
---@return string?
function M.get_cursor_path()
  local buf = view.current()
  local st = buf and view.bufs[buf]
  local line = view.cursor_line(buf)
  if not st or not line then
    return nil
  end
  if line.entry then
    return fs.join(line.entry.dir, line.entry.name)
  end
  return fs.join(st.dir, line.name)
end

--- A loam buffer was written: by `:w`, which applies the edits, or by joy's
--- auto-save, which doesn't.
---@param buf integer
---@param auto boolean
local function on_write(buf, auto)
  joy.fs.remove(view.cache_path(view.bufs[buf].dir))
  if saving or auto or config.options.apply_on_write == false then
    joy.buffer.set_modified(buf, true) -- the edits stay, unsaved, for a :w
    return
  end
  M.save({ written = buf })
end

--- The loam buffer of a directory, made the first time.
---@param dir string
---@return integer buf
---@return boolean new
local function buffer_for(dir)
  local buf = view.dir_bufs[dir]
  if buf and view.bufs[buf] and joy.buffer.get(buf) then
    return buf, false
  end
  fs.mkdirp(fs.parent(view.cache_path(dir)))
  -- Unlisted: the bufferline, :bn/:bp and the buffer picker skip it while
  -- no window shows it.
  buf = joy.buffer.create({ path = view.cache_path(dir), unlisted = true })
  -- Plain text, whatever the cache file's name says ("~%work%x.go").
  joy.buffer.set_language(buf, "")
  view.bufs[buf] = { dir = dir, ids = {}, lines = {} }
  view.dir_bufs[dir] = buf
  require("loam.keymaps").set_buffer(buf)
  return buf, true
end

--- Opens a directory in the current window: `dir`, else the current
--- file's (the cursor on it), else the current directory.
---@param dir? string
---@param opts? loam.OpenOpts
---@return integer? buf
function M.open(dir, opts)
  opts = opts or {}
  local focus = opts.focus
  local cur = joy.buffer.get(0)
  if dir == nil or dir == "" then
    local st = cur and view.bufs[cur.id]
    local name = cur and cur.path or ""
    if st then
      dir = st.dir
    elseif name ~= "" and not fs.is_dir(name) then
      dir = fs.parent(fs.normalize(name))
      focus = focus or fs.basename(name)
    else
      dir = joy.editor.get().cwd
    end
  end
  dir = fs.normalize(dir)
  if not fs.is_dir(dir) then
    joy.ui.notify("loam: not a directory: " .. dir, { level = "error" })
    return nil
  end
  local buf, new = buffer_for(dir)
  if opts.float then
    local float = config.options.float
    local width = float.width
    if width <= 1 then
      width = math.max(math.floor(joy.editor.get().width * width), 20)
    end
    local origin = joy.editor.get().window
    local vertical = float.side == "left" or float.side == "right"
    local win = joy.window.split(0, { buffer = buf, vertical = vertical,
      before = float.side == "left" or float.side == "above" })
    if win then
      if vertical then
        joy.window.resize(win, { width = math.floor(width) })
      end
      view.origins[win] = origin
    end
  elseif opts.split then
    joy.window.split(0, { buffer = buf, vertical = opts.split == "vertical" })
  else
    local win = opts.window or (cur and cur.window) or 0
    local shown = joy.window.get(win).buffer
    if not view.bufs[shown] then
      view.previous[win] = shown
    end
    joy.window.set_buffer(win, buf)
  end
  if new or not joy.buffer.get(buf).modified then
    view.render(buf, focus or false)
  end
  if focus then
    view.focus(buf, focus)
  end
  joy.ui.set_status("loam " .. mutator.display(dir) .. "/")
  return buf
end

--- Opens a directory in a window of its own.
---@param dir? string
---@return integer? buf
function M.open_float(dir)
  return M.open(dir, { float = true })
end

--- Closes loam: the buffer shown before it comes back (a float's window
--- closes). The loam buffer closes once nothing shows it, unless it has
--- edits, which wait for :w.
function M.close()
  local b = joy.buffer.get(0)
  if not b or not view.bufs[b.id] then
    return
  end
  local win = b.window
  local origin = view.origins[win]
  if origin then
    joy.window.close(win)
    if joy.window.get(origin) then
      joy.window.focus(origin)
    end
    return
  end
  local prev = view.previous[win]
  if prev and joy.buffer.get(prev) and not view.bufs[prev] then
    joy.window.set_buffer(win, prev)
  else
    joy.editor.exec("new") -- an empty buffer, as joy's own
  end
end

--- Closes the loam buffer of a directory that is gone; a window showing
--- it shows the nearest directory left instead.
---@param buf integer
local function drop(buf)
  local st = view.bufs[buf]
  local b = joy.buffer.get(buf)
  if b and b.visible and st then
    local dir = fs.parent(st.dir)
    while not fs.is_dir(dir) and dir ~= "/" do
      dir = fs.parent(dir)
    end
    M.open(dir, { window = b.window })
  end
  view.bufs[buf] = nil
  if st and view.dir_bufs[st.dir] == buf then
    view.dir_bufs[st.dir] = nil
  end
  pcall(joy.buffer.close, buf, { force = true })
end

--- Closes a loam buffer nothing shows, one with edits only when `force`,
--- so the buffers of every directory visited don't pile up and aren't
--- read again on each refresh; the next open reads its directory again.
---@param b joy.Buffer?
---@param force? boolean
local function release(b, force)
  if b and not b.visible and (force or not b.modified) then
    pcall(joy.buffer.close, b.id, { force = force })
  end
end

--- Reads the directories again, or closes the buffers nothing shows (the
--- next open reads them); buffers with edits only when `force`. Buffers of
--- directories that are gone close.
---@param force? boolean
function M.refresh_all(force)
  local bufs = {}
  for buf in pairs(view.bufs) do
    bufs[#bufs + 1] = buf
  end
  for _, buf in ipairs(bufs) do
    local st = view.bufs[buf]
    local b = st and joy.buffer.get(buf)
    if b then
      if not fs.is_dir(st.dir) then
        drop(buf)
      elseif not b.visible then
        release(b, force)
      elseif force or not b.modified then
        view.render(buf)
      end
    end
  end
end

--- Throws every loam buffer's edits away.
function M.discard_all_changes()
  M.refresh_all(true)
end

---@class loam.SaveOpts
---@field confirm? boolean false applies without asking; nil asks unless skip_confirm_for_simple_edits and the edits are simple.
---@field written? integer The buffer `:w` saved, which counts as modified again when nothing is applied.

--- Applies the edits of every loam buffer, after asking. Waits for the
--- answer: call it in a keymap, a command or joy.task.spawn.
---@param opts? loam.SaveOpts
---@return boolean applied
function M.save(opts)
  opts = opts or {}
  if saving then
    return false
  end
  saving = true
  local ok, res = pcall(M._save, opts)
  saving = false
  if not ok then
    joy.ui.notify("loam: " .. tostring(res), { level = "error" })
    return false
  end
  return res
end

---@param opts loam.SaveOpts
---@return boolean
function M._save(opts)
  local function keep_edits()
    if opts.written and view.bufs[opts.written] then
      joy.buffer.set_modified(opts.written, true)
    end
  end
  local actions, errors = mutator.compute()
  if #errors > 0 then
    keep_edits()
    joy.ui.notify("loam: nothing saved:\n" .. table.concat(errors, "\n"), { level = "error" })
    return false
  end
  if #actions == 0 then
    -- Nothing to do: tidy the buffers that differ only in blanks.
    M.refresh_all(true)
    return false
  end
  local ask = opts.confirm
  if ask == nil then
    ask = not (config.options.skip_confirm_for_simple_edits and mutator.is_simple(actions))
  end
  if ask then
    local answer = joy.ui.dialog("Apply " .. #actions .. (#actions == 1 and " change?" or " changes?"),
      { { label = "Yes", key = "y" }, { label = "No", key = "n" } },
      { content = mutator.describe(actions) })
    if answer ~= 0 then -- "No", or esc
      keep_edits()
      return false
    end
  end
  local moves = {}
  for _, a in ipairs(actions) do
    if a.type == "move" then
      moves[#moves + 1] = { a.src, a.dest }
    end
  end
  local err = mutator.apply(actions)
  M.follow_moves(moves)
  M.refresh_all(true)
  if err then
    joy.ui.notify("loam: " .. err, { level = "error" })
    return false
  end
  return true
end

--- Points the buffers of files that moved (or are in a directory that
--- did) at the files as they are now.
---@param moves {[1]: string, [2]: string}[]
function M.follow_moves(moves)
  for _, b in ipairs(joy.buffer.list()) do
    if not view.bufs[b.id] then
      local name = b.path
      for _, m in ipairs(moves) do
        if name ~= "" and fs.is_under(name, m[1]) then
          local to = m[2] .. name:sub(#m[1] + 1)
          if fs.exists(to) and not fs.exists(name) or name:lower() == to:lower() then
            joy.buffer.set_path(b.id, to)
          end
          break
        end
      end
    end
  end
end

--- Shows hidden files, or hides them.
---@param show? boolean
function M.toggle_hidden(show)
  local v = config.options.view_options
  if show == nil then
    show = not v.show_hidden
  end
  v.show_hidden = show
  local skipped = false
  for buf in pairs(view.bufs) do
    local b = joy.buffer.get(buf)
    if b then
      if b.modified then
        skipped = true
      else
        view.render(buf)
      end
    end
  end
  if skipped then
    joy.ui.notify("loam: buffers with unsaved edits show the change once saved or refreshed", { level = "warning" })
  end
end

--- Sorts by these columns: { { "type", "asc" }, { "mtime", "desc" } }.
---@param sort loam.SortSpec[]
function M.set_sort(sort)
  config.options.view_options.sort = sort
  M.refresh_all(false)
end

--- Shows these columns: { "icon", "permissions", "size", "mtime" }.
---@param columns (string|table)[]
function M.set_columns(columns)
  config.options.columns = columns
  for buf in pairs(view.bufs) do
    view.decorate(buf)
  end
end

--- The startup directory joy was given (`joy .`), shown in loam when it is
--- the default file explorer.
---@param args? string[]
function M.on_startup(args)
  if not config.options.default_file_explorer then
    return
  end
  for _, arg in ipairs(args or joy.editor.get().args) do
    if fs.is_dir(arg) then
      pcall(joy.editor.exec, "tree-close") -- joy opens its file tree for a directory
      local start = joy.buffer.get(0) -- joy's empty start buffer, which goes
      if start and (start.path ~= "" or start.modified or start.size > 0) then
        start = nil
      end
      if M.open(arg) and start and not view.bufs[start.id] then
        pcall(joy.buffer.close, start.id)
      end
      return
    end
  end
end

--- `-` anywhere: the directory of the current file, the cursor on it.
function M.open_parent()
  if view.bufs[view.current()] then
    return require("loam.actions").parent()
  end
  M.open()
end

-- The events of every loam buffer.
joy.on("buffer_changed", function(e)
  if view.bufs[e.buffer] then
    view.decorate(e.buffer)
  end
end)
joy.on("cursor_moved", function(e)
  if not view.bufs[e.buffer] then
    return
  end
  view.constrain(e.buffer)
  if e.mode ~= "insert" then
    require("loam.actions").update_preview(e.buffer)
  end
end)
joy.on("mode_changed", function(e)
  if view.bufs[e.buffer] and e.mode == "insert" then
    view.constrain(e.buffer)
  end
end)
joy.on("buffer_saved", function(e)
  if view.bufs[e.buffer] then
    on_write(e.buffer, e.auto)
  end
end)
joy.on("window_focus_changed", function(e)
  if view.bufs[e.previous_buffer] then
    joy.ui.set_status("")
    release(joy.buffer.get(e.previous_buffer))
  end
  local st = view.bufs[e.buffer]
  if not st then
    return
  end
  joy.ui.set_status("loam " .. mutator.display(st.dir) .. "/")
  if not fs.is_dir(st.dir) then
    M.refresh_all(false) -- gone: the nearest directory left instead
  elseif not joy.buffer.get(e.buffer).modified and not saving then
    view.render(e.buffer)
  else
    view.decorate(e.buffer)
  end
end)
joy.on("buffer_closed", function(e)
  local st = view.bufs[e.buffer]
  if st and view.dir_bufs[st.dir] == e.buffer then
    view.dir_bufs[st.dir] = nil
  end
  view.bufs[e.buffer] = nil
end)
joy.on("window_closed", function(e)
  view.origins[e.window], view.previous[e.window] = nil, nil
  require("loam.actions").window_closed(e.window)
end)

return M
