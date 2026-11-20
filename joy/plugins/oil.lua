-- oil: edit directories as text, like oil.nvim. :Oil (or - in vim normal
-- mode) opens the directory of the current file as a buffer with a line
-- per entry. Rename by editing a name, delete by deleting a line, create
-- by adding one (end it with / for a directory), move or copy by cutting
-- or yanking lines into the buffer of another directory. Saving lists the
-- changes and asks before applying them. enter opens the entry under the
-- cursor, - the parent directory, :OilHidden shows dotfiles.
--
-- Each line starts with an id, "/12 name", that ties it to the file it was
-- listed for; lines without one are new.

local ids, by_path, next_id = {}, {}, 0
local views = {} -- listing file -> {dir, orig = {ids}}
local hidden = false
local pending
local pending_cursor = {} -- listing file -> cursor to set once it is shown
local open_entry

local tmp = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "") .. "/joy-oil"

local function color(role, text)
  return joy.ui.render({ { text = text, style = { link = role } } })
end

-- relative shows path relative to the working directory.
local function relative(path, cwd)
  cwd = (cwd or joy.editor.get().cwd) .. "/"
  if path:sub(1, #cwd) == cwd then return path:sub(#cwd + 1) end
  return path
end

local function id_for(path)
  if not by_path[path] then
    next_id = next_id + 1
    ids[next_id], by_path[path] = path, next_id
  end
  return by_path[path]
end

local function parent(path) return path:match("^(.*)/[^/]+/?$") or "/" end
local function base(path) return path:match("([^/]+)/?$") or path end

local function is_dir(path)
  local stat = joy.fs.stat(path)
  return stat ~= nil and (stat.type == "directory" or (stat.type == "link" and stat.target_type == "directory"))
end

local function listing(dir)
  local entries = joy.fs.list(dir)
  if not entries then return nil end
  local dirs, files = {}, {}
  for _, entry in ipairs(entries) do
    local name = entry.name
    if name ~= ".git" and name ~= ".DS_Store" and (hidden or not name:match("^%.")) then
      local path = joy.fs.join(dir, name)
      if entry.type == "directory" or (entry.type == "link" and is_dir(path)) then
        dirs[#dirs + 1] = name
      else
        files[#files + 1] = name
      end
    end
  end
  local function by_name(a, b) return a:lower() < b:lower() end
  table.sort(dirs, by_name)
  table.sort(files, by_name)
  local lines, orig = {}, {}
  for _, name in ipairs(dirs) do
    local id = id_for(joy.fs.join(dir, name))
    lines[#lines + 1], orig[#orig + 1] = "/" .. id .. " " .. name .. "/", id
  end
  for _, name in ipairs(files) do
    local id = id_for(joy.fs.join(dir, name))
    lines[#lines + 1], orig[#orig + 1] = "/" .. id .. " " .. name, id
  end
  return lines, orig
end

local function view_of(buf)
  local b = joy.buffer.get(buf or 0)
  return b and views[b.path] or nil
end

local function parse(line)
  local id, name = line:match("^/(%d+) (.*)$")
  if id then return tonumber(id), name end
  return nil, line
end

local function decorate(buf)
  if not view_of(buf) then return end
  local lines = joy.buffer.get_lines(buf, 0, -1)
  if not lines then return end
  local items = {}
  for i, line in ipairs(lines) do
    local prefix = line:match("^/%d+ ")
    if prefix then
      items[#items + 1] = {
        row = i - 1, col = 0, end_row = i - 1, end_col = #prefix,
        style = { link = "muted" },
      }
    end
    if line:match("/$") then
      items[#items + 1] = {
        row = i - 1, col = prefix and #prefix or 0, end_row = i - 1, end_col = #line,
        style = { link = "tree-dir", bold = true },
      }
    end
  end
  joy.buffer.decorate(buf, "oil", { highlights = items })
end

local function prepare_buffer(buf)
  local b = joy.buffer.get(buf)
  if not b or not views[b.path] then return end
  if b.language ~= "" then joy.buffer.set_language(buf, "") end
  joy.keymap.set("oil-open-entry", "enter", open_entry, {
    when = "normal", buffer = buf, desc = "Open the entry under the cursor", no_wait = true,
  })
end

-- show lists dir in the current window, with the cursor on focus.
-- buffer_of returns the open buffer of the listing file, or nil. Only that
-- buffer is ever written to: never "the current one", which is still the
-- previous file until joy has opened the listing.
local function buffer_of(file)
  for _, b in ipairs(joy.buffer.list()) do
    if b.path == file then return b.id end
  end
end

local function place_cursor(buf, file)
  local at = pending_cursor[file]
  local b = joy.buffer.get(buf)
  if not at or not b or b.path ~= file then return end
  pending_cursor[file] = nil
  joy.buffer.set_cursor(buf, at)
  decorate(buf)
end

-- show lists dir in the current window, with the cursor on focus.
local function show(dir, focus)
  local lines, orig = listing(dir)
  if not lines then return joy.ui.notify(dir .. " is not a directory") end
  local file = tmp .. "/" .. joy.util.sha256(dir):sub(1, 12) .. "/" .. base(dir) .. ".oil"
  views[file] = { dir = dir, orig = orig }
  -- An open listing is updated in its buffer and saved; writing the file
  -- under it would make joy reload it while it is being edited.
  local open_buf = buffer_of(file)
  local updated = false
  if open_buf then
    if table.concat(joy.buffer.get_lines(open_buf, 0, -1), "\n") == table.concat(lines, "\n") then
      updated = true
    else
      updated = pcall(joy.buffer.set_lines, open_buf, 0, -1, lines) and pcall(joy.buffer.save, open_buf)
    end
  end
  if not updated then
    joy.fs.mkdir(file:match("^(.*)/[^/]*$"))
    joy.fs.write(file, table.concat(lines, "\n") .. "\n")
  end
  local row = 1
  for i, l in ipairs(lines) do
    local _, name = parse(l)
    if name == focus then row = i end
  end
  local prefix = (lines[row] or ""):match("^/%d+ ")
  pending_cursor[file] = { row = row - 1, col = prefix and #prefix or 0 }
  local buf = joy.buffer.open(file, { cursor = pending_cursor[file], unlisted = true })
  if buf then
    prepare_buffer(buf)
    place_cursor(buf, file) -- else when joy shows it
  end
  joy.ui.notify(relative(dir) .. "/")
end

local function open_buffer(args)
  local current = joy.buffer.get(0)
  local v = current and views[current.path] or nil
  local dir, focus
  if args and args ~= "" then
    dir = joy.fs.abspath(args)
  elseif v then
    dir, focus = parent(v.dir), base(v.dir) .. "/"
  elseif current and current.path ~= "" then
    dir, focus = parent(current.path), base(current.path)
  else
    dir = joy.editor.get().cwd
  end
  if v and current.modified then return joy.ui.notify("Save (:w) or undo the changes to this directory first") end
  show(dir, focus)
end

open_entry = function()
  local current = joy.buffer.get(0)
  local v = current and views[current.path] or nil
  if not v then return end
  local row = current.cursor.row
  local _, name = parse(joy.buffer.get_lines(0, row, row + 1)[1] or "")
  name = joy.util.trim(name or "")
  if name == "" then return end
  local path = joy.fs.join(v.dir, (name:gsub("/$", "")))
  if name:match("/$") or is_dir(path) then
    if current.modified then return joy.ui.notify("Save (:w) or undo the changes to this directory first") end
    return show(path)
  end
  if not joy.fs.exists(path) then return joy.ui.notify(name .. " does not exist yet; save (:w) to create it") end
  joy.buffer.open(path)
end

-- plan compares every directory buffer with its listing.
local function plan()
  local dests, listed, creates, errs = {}, {}, {}, {}
  for _, b in ipairs(joy.buffer.list()) do
    local buf = b.id
    local v = views[b.path]
    if v then
      for _, id in ipairs(v.orig) do listed[id] = true end
      for _, line in ipairs(joy.buffer.get_lines(buf, 0, -1)) do
        local id, name = parse(line)
        name = joy.util.trim(name)
        if name ~= "" then
          if name == "." or name == ".." or name:match("^%.%./") or name:match("^/") then
            errs[#errs + 1] = "bad name " .. name
          else
            local to = joy.fs.join(v.dir, (name:gsub("/$", "")))
            if id and ids[id] then
              dests[id] = dests[id] or {}
              table.insert(dests[id], to)
            else
              creates[#creates + 1] = { kind = name:match("/$") and "mkdir" or "create", to = to }
            end
          end
        end
      end
    end
  end
  if #errs > 0 then return nil, table.concat(errs, ", ") end
  local all = {}
  for id in pairs(listed) do all[id] = true end
  for id in pairs(dests) do all[id] = true end
  local sorted = {}
  for id in pairs(all) do sorted[#sorted + 1] = id end
  table.sort(sorted)
  local copies, moves, deletes = {}, {}, {}
  for _, id in ipairs(sorted) do
    local src, to = ids[id], dests[id] or {}
    if #to == 0 then
      if listed[id] then deletes[#deletes + 1] = { kind = "delete", from = src } end
    else
      local stays = false
      for _, t in ipairs(to) do stays = stays or t == src end
      local moved = not stays and listed[id]
      local seen = {}
      for _, t in ipairs(to) do
        if t ~= src and not seen[t] then
          seen[t] = true
          if moved then
            moves[#moves + 1] = { kind = "move", from = src, to = t }
            moved = false
          else
            copies[#copies + 1] = { kind = "copy", from = src, to = t }
          end
        end
      end
    end
  end
  -- Copies read their files before moves take them away.
  local ops = creates
  for _, list in ipairs({ copies, moves, deletes }) do
    for _, op in ipairs(list) do ops[#ops + 1] = op end
  end
  return ops
end

local function refresh_all()
  for _, b in ipairs(joy.buffer.list()) do
    local buf = b.id
    local v = views[b.path]
    if v then
      local lines, orig = listing(v.dir)
      if lines then
        v.orig = orig
        if not (pcall(joy.buffer.set_lines, buf, 0, -1, lines) and pcall(joy.buffer.save, buf)) then
          joy.fs.write(b.path, table.concat(lines, "\n") .. "\n") -- joy reloads it
        end
        prepare_buffer(buf)
        decorate(buf)
      end
    end
  end
end

local function sh(argv)
  local res, err = joy.process.run(argv)
  if not res then return err end
  if res.code ~= 0 then return joy.util.trim(res.stderr) end
end

local function apply()
  local ops = pending
  pending = nil
  local done, failed = 0, {}
  for _, op in ipairs(ops) do
    local err
    if op.kind == "mkdir" then
      err = sh({ "mkdir", "-p", op.to })
    elseif op.kind == "create" then
      if joy.fs.exists(op.to) then err = "exists" else
        joy.fs.mkdir(parent(op.to))
        joy.fs.write(op.to, "")
      end
    elseif op.kind == "move" or op.kind == "copy" then
      if joy.fs.exists(op.to) then err = relative(op.to) .. " exists" else
        joy.fs.mkdir(parent(op.to))
        err = sh(op.kind == "move" and { "mv", op.from, op.to } or { "cp", "-R", op.from, op.to })
        if not err and op.kind == "move" then
          local id = by_path[op.from]
          by_path[op.from], by_path[op.to], ids[id] = nil, id, op.to
        end
      end
    elseif op.kind == "delete" then
      err = sh({ "rm", "-rf", "--", op.from })
    end
    if err then failed[#failed + 1] = op.kind .. " " .. relative(op.to or op.from) .. ": " .. err else done = done + 1 end
  end
  refresh_all()
  if #failed > 0 then
    joy.ui.notify(done .. " change(s) applied; failed: " .. table.concat(failed, "; "), { level = "error" })
  else
    joy.ui.notify(done .. " change(s) applied")
  end
end

local function confirm(ops)
  local rows = {}
  for _, op in ipairs(ops) do
    local text
    if op.kind == "create" or op.kind == "mkdir" then
      text = color("git-add", "CREATE ") .. relative(op.to) .. (op.kind == "mkdir" and "/" or "")
    elseif op.kind == "delete" then
      text = color("git-delete", "DELETE ") .. relative(op.from)
    else
      text = color("git-change", (op.kind == "move" and "MOVE   " or "COPY   ")) .. relative(op.from) .. color("muted", " → ") .. relative(op.to)
    end
    rows[#rows + 1] = text
  end
  joy.ui.panel("oil-confirm", rows, {
    title = string.format("Apply %d change(s)?  y apply · n cancel", #ops),
    cursor = { row = 0, col = 0 },
    on_key = function(key)
      if key == "y" then
        joy.ui.close("oil-confirm")
        apply()
      elseif key == "n" or key == "q" or key == "esc" then
        pending = nil
        joy.ui.close("oil-confirm")
        joy.ui.notify("Nothing changed; the buffers keep your edits")
      end
    end,
  })
end

joy.on("buffer_saved", function(ev)
  if not views[ev.path] or pending then return end
  local ops, err = plan()
  if not ops then return joy.ui.notify(err, { level = "error" }) end
  if #ops == 0 then return end
  pending = ops
  confirm(ops)
end)

joy.on("buffer_opened", function(ev)
  if views[ev.path] then
    prepare_buffer(ev.buffer)
    decorate(ev.buffer)
  end
end)

-- enter opens entries only in directory buffers.
joy.on("window_focus_changed", function(ev)
  local b = joy.buffer.get(ev.buffer)
  if not b or not views[b.path] then return end
  prepare_buffer(ev.buffer)
  decorate(ev.buffer)
  place_cursor(ev.buffer, b.path)
end)
joy.on("buffer_changed", function(ev) decorate(ev.buffer) end)

local mounted

local function tree_entries(dir)
  local entries = joy.fs.list(dir)
  if not entries then return nil end
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.name ~= ".git" and entry.name ~= ".DS_Store" and (hidden or not entry.name:match("^%.")) then
      local path = joy.fs.join(dir, entry.name)
      out[#out + 1] = {
        name = entry.name, path = path,
        directory = entry.type == "directory" or (entry.type == "link" and is_dir(path)),
      }
    end
  end
  table.sort(out, function(a, b)
    if a.directory ~= b.directory then return a.directory end
    return a.name:lower() < b.name:lower()
  end)
  -- ./ and ../ come first, to stay put or go up.
  if dir ~= "/" then table.insert(out, 1, { name = "..", path = parent(dir), directory = true, up = true }) end
  table.insert(out, 1, { name = ".", path = dir, directory = true, here = true })
  return out
end

local function select_named(m, focus)
  m.selected = 1
  for i, entry in ipairs(m.entries) do
    if not entry.here and not entry.up then
      m.selected = i
      break
    end
  end
  for i, entry in ipairs(m.entries) do
    if entry.name == focus or entry.name .. "/" == focus then
      m.selected = i
      return
    end
  end
end

-- follow is the directory of the file last focused, which the tree shows
-- whenever it gets the focus.
local follow

local function reload(m, dir, focus)
  local entries = tree_entries(dir)
  if not entries then return end
  m.dir, m.entries = dir, entries
  select_named(m, focus)
end

local function hide()
  joy.timer.after(0, function() pcall(joy.editor.exec, "tree-close") end)
end

local function tree_model(m)
  return {
    init = function() return m, nil end,
    update = function(m, msg)
      if msg.type == "focus" then
        if follow and follow.dir ~= m.dir then reload(m, follow.dir, follow.name) end
        return m, nil
      end
      if msg.type ~= "key" then return m, nil end
      if msg.key == "space" then
        m.space = true
        return m, nil
      end
      local space = m.space
      m.space = false
      if (space and msg.key == "e") or msg.key == "q" or msg.key == "esc" or msg.key == "ctrl+c" then
        hide()
      elseif msg.key == "e" then
        local dir = m.dir
        hide()
        joy.timer.after(0, function() open_buffer(dir) end)
      elseif msg.key == "j" or msg.key == "down" then
        m.selected = math.min(m.selected + 1, #m.entries)
      elseif msg.key == "k" or msg.key == "up" then
        m.selected = math.max(m.selected - 1, 1)
      elseif msg.key == "G" then
        m.selected = math.max(#m.entries, 1)
      elseif msg.key == "g" or msg.key == "home" then
        m.selected = 1
      elseif msg.key == "-" or msg.key == "h" or msg.key == "left" then
        reload(m, parent(m.dir), base(m.dir))
      elseif msg.key == "." then
        hidden = not hidden
        reload(m, m.dir, (m.entries[m.selected] or {}).name)
      elseif msg.key == "r" then
        reload(m, m.dir, (m.entries[m.selected] or {}).name)
      elseif msg.key == "enter" or msg.key == "ctrl+m" or msg.key == "l" or msg.key == "right" then
        local entry = m.entries[m.selected]
        if entry and entry.up then
          reload(m, parent(m.dir), base(m.dir))
        elseif entry and entry.directory then
          reload(m, entry.path, entry.here and "." or nil)
        elseif entry then
          local path = entry.path
          joy.timer.after(0, function()
            local ok, err = pcall(joy.buffer.open, path)
            if not ok then joy.ui.notify(tostring(err), { level = "error" }) end
          end)
        end
      end
      return m, nil
    end,
    view = function(m)
      local lines = { (m.dir == m.cwd and base(m.dir) or relative(m.dir, m.cwd)) .. "/", "" }
      for i, entry in ipairs(m.entries) do
        lines[#lines + 1] = (i == m.selected and "> " or "  ") .. entry.name .. (entry.directory and "/" or "")
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = "enter open · - parent · e edit · . hidden · q close"
      return table.concat(lines, "\n")
    end,
  }
end

-- register makes Oil joy's file tree: hidden until any way of opening the
-- tree (alt+e, space e, :tree, start-up) shows it.
local function register()
  local cwd = joy.editor.get().cwd
  local b = joy.buffer.get(0)
  if b and b.path ~= "" then follow = { dir = parent(b.path), name = base(b.path) } end
  local dir = follow and follow.dir or cwd
  local m = { dir = dir, entries = tree_entries(dir) or {}, selected = 1, cwd = cwd }
  select_named(m, follow and follow.name)
  local ok, err = pcall(joy.ui.mount, "oil-tree", tree_model(m), {
    replace = "file_tree", fullscreen = true, keep_focus = true,
  })
  if not ok then joy.ui.notify("oil: " .. tostring(err), { level = "error" }) end
end

joy.on("ready", register)
joy.on("window_focus_changed", function(ev)
  local b = joy.buffer.get(ev.buffer)
  if b and b.path ~= "" and not views[b.path] then
    follow = { dir = parent(b.path), name = base(b.path) }
  end
end)

joy.command.set("Oil", function() joy.editor.exec("tree") end, {
  desc = "Show Oil, joy's file tree",
})
joy.command.set("OilEdit", function(cmd) open_buffer(cmd.args) end, {
  desc = "Edit a directory as text (:OilEdit [dir])", complete = "dir",
})
joy.command.set("OilHidden", function()
  hidden = not hidden
  refresh_all()
end, { desc = "Show or hide dotfiles in Oil" })
