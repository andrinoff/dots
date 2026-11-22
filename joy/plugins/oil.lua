-- oil: joy's file tree is an editable directory listing, like oil.nvim. Any
-- way into the tree (space e, alt+e, :tree) shows it over every window.
-- Edit it as text: rename an entry by editing its name, delete one by
-- deleting its line, create one by adding a line (end it with / for a
-- directory), copy one by yanking its line and pasting it in another
-- directory, move one by cutting its line and pasting it in another directory
-- or by renaming it to ../name or dir/name. A directory left with edits keeps
-- them: :w lists the changes of every directory and asks before applying them.
-- enter opens the entry under the cursor (./ reads the directory again, ../
-- goes up), - goes up, g . shows or hides dotfiles, q closes. The cursor stays
-- on its row from one directory to the next. Dotfiles and ignored names follow
-- show-hidden and ignore of [file-tree] in config.toml, as joy's own tree.
--
-- The listing is only names. Which file each line stands for is kept here,
-- not in the text: every change is compared with the lines before it, so a
-- line keeps its file as it is edited. A line pasted, or undone, is the file
-- of that name whose line was deleted, or listed in a directory you left:
-- moved or copied. A line typed is new.

local COLOR = "#5eacd3"

local ids, by_path, next_id = {}, {}, 0
local hidden, ignored -- [file-tree]'s show-hidden and ignore, read once
local buf -- the listing buffer, which is joy's file tree
-- The directory listed, the ids of the files it listed, and its lines as last
-- seen with the id of each line (false for none).
local view = { dir = nil, orig = {}, lines = {}, ids = {} }
local pending = {} -- dir -> { lines, ids, orig }: listings left with edits, for :w
local recent = {} -- name -> { id, dir }: entries whose lines were deleted, to paste
local seen = {} -- name -> { id, dir }: entries of the directories left, to paste
local rendering -- render is replacing the lines: they aren't edits
local follow -- the file focused last: where the tree opens

local tmp = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "") .. "/joy-oil"

local function parent(path) return path:match("^(.*)/[^/]+/?$") or "/" end
local function base(path) return path:match("([^/]+)/?$") or path end

-- clean resolves the . and .. of an absolute path.
local function clean(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then parts[#parts] = nil elseif part ~= "." then parts[#parts + 1] = part end
  end
  return "/" .. table.concat(parts, "/")
end

-- relative shows path relative to the working directory.
local function relative(path)
  local cwd = joy.editor.get().cwd .. "/"
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

local function is_dir(path)
  local stat = joy.fs.stat(path)
  return stat ~= nil and (stat.type == "directory" or (stat.type == "link" and stat.target_type == "directory"))
end

-- tree_config reads show-hidden and ignore of [file-tree] in config.toml, with
-- joy's defaults for what it leaves out. ponytail: only those two keys, no
-- full TOML; an ignore array may span lines.
local function tree_config()
  local show, ignore = false, { ".git", ".DS_Store", "node_modules" }
  local text = joy.fs.read(joy.fs.join(joy.editor.get().dirs.config, "config.toml"))
  if text then
    local body, inside = {}, false
    for line in (text .. "\n"):gmatch("(.-)\n") do
      local header = line:match("^%s*%[([^%]]*)%]")
      if header then
        inside = header == "file-tree"
      elseif inside and not line:match("^%s*#") then
        body[#body + 1] = line
      end
    end
    body = table.concat(body, "\n")
    show = body:match("show%-hidden%s*=%s*(%a+)") == "true"
    local list = body:match("ignore%s*=%s*(%b[])")
    if list then
      ignore = {}
      for name in list:gmatch("[\"']([^\"']*)[\"']") do ignore[#ignore + 1] = name end
    end
  end
  local set = {}
  for _, name in ipairs(ignore) do set[name] = true end
  return show, set
end

local function trim(s) return joy.util.trim(s or "") end

-- listing is dir's lines, ./ and ../, then its directories, then its files,
-- the id of each line, and the ids of its entries.
local function listing(dir)
  local entries = joy.fs.list(dir)
  if not entries then return nil end
  local dirs, files = {}, {}
  for _, entry in ipairs(entries) do
    local name = entry.name
    if not ignored[name] and (hidden or not name:match("^%.")) then
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
  local lines, line_ids, orig = { "./" }, { false }, {}
  if dir ~= "/" then lines[2], line_ids[2] = "../", false end
  for _, list in ipairs({ dirs, files }) do
    for _, name in ipairs(list) do
      local id = id_for(joy.fs.join(dir, name))
      lines[#lines + 1], line_ids[#line_ids + 1], orig[#orig + 1] = list == dirs and name .. "/" or name, id, id
    end
  end
  return lines, line_ids, orig
end

-- carry gives new, the lines after a change, the ids of old, the lines before
-- it: a line the change left keeps its id, and one it changed takes the id of
-- the line it replaced. It returns their ids, the lines it added whole, as a
-- paste does, and the lines removed with ids.
local function carry(old, old_ids, new)
  local n, m, p, s = #old, #new, 0, 0
  while p < n and p < m and old[p + 1] == new[p + 1] do p = p + 1 end
  while s < n - p and s < m - p and old[n - s] == new[m - s] do s = s + 1 end
  local out, fresh, removed = {}, {}, {}
  for i = 1, p do out[i] = old_ids[i] end
  for i = 0, s - 1 do out[m - i] = old_ids[n - i] end
  -- In between, lines that stayed are found by a longest common subsequence;
  -- the others pair up in order. ponytail: no LCS past 500x500 lines.
  local a, b = n - s - p, m - s - p
  local lcs = {}
  if a * b <= 250000 then
    for i = a + 1, 1, -1 do
      lcs[i] = {}
      for j = b + 1, 1, -1 do
        if i > a or j > b then lcs[i][j] = 0
        elseif old[p + i] == new[p + j] then lcs[i][j] = lcs[i + 1][j + 1] + 1
        else lcs[i][j] = math.max(lcs[i + 1][j], lcs[i][j + 1]) end
      end
    end
  end
  local gone, added = {}, {}
  local function pair()
    for k = 1, math.max(#gone, #added) do
      local i, j = gone[k], added[k]
      if j then
        out[p + j] = i and old_ids[p + i] or false
        fresh[p + j] = not i
      elseif old_ids[p + i] then removed[#removed + 1] = { id = old_ids[p + i], name = trim(old[p + i]) } end
    end
    gone, added = {}, {}
  end
  local i, j = 1, 1
  while i <= a or j <= b do
    if i <= a and j <= b and lcs[1] and old[p + i] == new[p + j] then
      pair()
      out[p + j] = old_ids[p + i]
      i, j = i + 1, j + 1
    elseif j > b or (i <= a and lcs[1] and lcs[i + 1][j] >= lcs[i][j + 1]) or (i <= a and not lcs[1] and #gone <= #added) then
      gone[#gone + 1] = i
      i = i + 1
    else
      added[#added + 1] = j
      j = j + 1
    end
  end
  pair()
  return out, fresh, removed
end

-- sync follows the listing's changes since it was last seen, so each line
-- keeps the file it stands for. A line that arrives whole, pasted or undone,
-- is the entry of that name deleted or seen in another directory: moved or
-- copied. One typed is new.
local function sync()
  local now = view.dir and not rendering and joy.buffer.get_lines(buf, 0, -1)
  if not now then return end
  local line_ids, fresh, removed = carry(view.lines, view.ids, now)
  for _, r in ipairs(removed) do recent[r.name] = { id = r.id, dir = view.dir } end
  for i, line in ipairs(now) do
    local name = trim(line)
    local s = seen[name]
    local r = recent[name] or (s and s.dir ~= view.dir and s)
    if fresh[i] and r then line_ids[i] = r.id end
  end
  view.lines, view.ids = now, line_ids
end

-- decorate colors the directories.
local function decorate()
  local items = {}
  for i, line in ipairs(joy.buffer.get_lines(buf, 0, -1) or {}) do
    if line:match("/%s*$") then
      items[#items + 1] = { row = i - 1, col = 0, end_row = i - 1, end_col = #line, style = { fg = COLOR, bold = true } }
    end
  end
  joy.buffer.decorate(buf, "oil", { highlights = items })
end

-- render lists dir in the buffer, or shows the edits it was left with, the
-- cursor on the entry named focus, or on row, or on its first entry.
local function render(dir, focus, row)
  local kept = pending[dir]
  local lines, line_ids, orig
  if kept then
    pending[dir], lines, line_ids, orig = nil, kept.lines, kept.ids, kept.orig
  else
    lines, line_ids, orig = listing(dir)
    if not lines then return joy.ui.notify(dir .. " is not a directory", { level = "error" }) end
  end
  view.dir, view.orig, view.lines, view.ids = dir, orig, lines, line_ids
  rendering = true
  local path = tmp .. "/" .. joy.util.sha256(dir):sub(1, 12) .. "/" .. (dir == "/" and "root" or base(dir))
  joy.fs.mkdir(parent(path))
  if joy.buffer.get(buf).path ~= path then
    -- A listing a restored session reopened as a file has the path: it goes.
    for _, b in ipairs(joy.buffer.list()) do
      if b.id ~= buf and b.path == path then pcall(joy.buffer.close, b.id, { force = true }) end
    end
    joy.buffer.set_path(buf, path)
    joy.buffer.set_language(buf, "")
  end
  joy.buffer.set_lines(buf, 0, -1, lines)
  joy.buffer.set_modified(buf, kept ~= nil)
  rendering = false
  decorate()
  row = math.min(row or 3, #lines)
  for i, line in ipairs(lines) do
    if focus and (line == focus or line == focus .. "/") then row = i end
  end
  joy.buffer.set_cursor(buf, { row = row - 1, col = 0 })
end

-- leave keeps what the listing shown holds before another replaces it: its
-- edits, for :w, and its entries, to paste in another directory.
local function leave()
  sync()
  for i, line in ipairs(view.lines) do
    if view.ids[i] then seen[trim(line)] = { id = view.ids[i], dir = view.dir } end
  end
  if joy.buffer.get(buf).modified then
    pending[view.dir] = { lines = view.lines, ids = view.ids, orig = view.orig }
  end
end

-- go lists another directory, the cursor on the row it was on. The listing's
-- edits wait for :w.
local function go(dir)
  local row = joy.buffer.get(buf).cursor.row
  leave()
  render(dir, nil, row + 1)
end

local function open_entry()
  local row = joy.buffer.get(buf).cursor.row
  local name = trim(joy.buffer.get_lines(buf, row, row + 1)[1])
  if name == "" then return end
  if name == "./" or name == "." then return go(view.dir) end
  if name == "../" or name == ".." then return go(parent(view.dir)) end
  local path = joy.fs.join(view.dir, (name:gsub("/$", "")))
  if name:match("/$") or is_dir(path) then return go(path) end
  if not joy.fs.exists(path) then return joy.ui.notify(name .. " does not exist yet; save (:w) to create it") end
  -- The tree closes first, so the file opens in the window it was shown in.
  joy.editor.exec("tree-close")
  joy.buffer.open(path)
end

-- plan compares the listings, the one shown and those left with edits, with
-- what they listed: an entry that left one directory for another moves.
local function plan()
  sync()
  local dests, listed, creates, errs = {}, {}, {}, {}
  local listings = { { dir = view.dir, lines = view.lines, ids = view.ids, orig = view.orig } }
  for dir, kept in pairs(pending) do
    listings[#listings + 1] = { dir = dir, lines = kept.lines, ids = kept.ids, orig = kept.orig }
  end
  for _, l in ipairs(listings) do
    for _, id in ipairs(l.orig) do listed[id] = true end
    for i, line in ipairs(l.lines) do
      local id, name = l.ids[i], trim(line)
      if name == "" or name == "./" or name == "../" or name == "." or name == ".." then
        -- nothing, or the navigation lines
      elseif name:match("^/") then
        errs[#errs + 1] = "bad name " .. name
      else
        local to = clean(joy.fs.join(l.dir, (name:gsub("/$", ""))))
        if id and ids[id] then
          dests[id] = dests[id] or {}
          table.insert(dests[id], to)
        else
          creates[#creates + 1] = { kind = name:match("/$") and "mkdir" or "create", to = to }
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

local function sh(argv)
  local res, err = joy.process.run(argv)
  if not res then return err end
  if res.code ~= 0 then return joy.util.trim(res.stderr) end
end

local function apply(ops)
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
  local row = joy.buffer.get(buf).cursor.row
  local name = trim(joy.buffer.get_lines(buf, row, row + 1)[1])
  pending, recent, seen = {}, {}, {}
  render(view.dir, name)
  if #failed > 0 then
    joy.ui.notify(done .. " change(s) applied; failed: " .. table.concat(failed, "; "), { level = "error" })
  else
    joy.ui.notify(done .. " change(s) applied")
  end
end

joy.on("buffer_saved", function(ev)
  if ev.buffer ~= buf then return end
  if ev.auto then
    joy.buffer.set_modified(buf, true) -- the edits wait for a :w
    return
  end
  local ops, err = plan()
  if not ops then return joy.ui.notify(err, { level = "error" }) end
  if #ops == 0 then return end
  local rows = {}
  for _, op in ipairs(ops) do
    if op.kind == "create" or op.kind == "mkdir" then
      rows[#rows + 1] = "+ create " .. relative(op.to) .. (op.kind == "mkdir" and "/" or "")
    elseif op.kind == "delete" then
      rows[#rows + 1] = "- delete " .. relative(op.from)
    else
      rows[#rows + 1] = "  " .. op.kind .. " " .. relative(op.from) .. " → " .. relative(op.to)
    end
  end
  local choice = joy.ui.dialog(string.format("Apply %d change(s)?", #ops),
    { { label = "Apply", key = "y" }, { label = "Cancel", key = "n" } }, { content = rows, kind = "diff" })
  if choice == 0 then
    apply(ops)
  else
    joy.buffer.set_modified(buf, true)
    joy.ui.notify("Nothing changed; the listing keeps your edits")
  end
end)

joy.on("buffer_changed", function(ev)
  if ev.buffer ~= buf then return end
  sync()
  decorate()
end)

joy.on("window_focus_changed", function(ev)
  local b = joy.buffer.get(ev.buffer)
  if b and b.path ~= "" and ev.buffer ~= buf then
    follow = { dir = parent(b.path), name = base(b.path) }
  end
end)

-- tree is the mount that makes the listing joy's file tree. Its model only
-- hears when the tree shows, to list the directory of the file focused last.
local tree = {
  init = function() return 0, nil end,
  update = function(m, msg)
    if msg.type == "focus" then
      joy.timer.after(0, function()
        local b = joy.buffer.get(buf)
        if b and not b.modified and follow and follow.dir ~= view.dir then
          leave()
          render(follow.dir, follow.name)
        end
      end)
    end
    return m, nil
  end,
  view = function() return "" end,
}

-- register makes a new listing buffer joy's file tree: at start-up, and
-- again when the listing closed, as when Restore Session or a project
-- replaced every window.
local function register()
  pcall(joy.ui.close, "oil-tree")
  local current = joy.buffer.get(0)
  if current and current.path ~= "" and current.id ~= buf then
    follow = { dir = parent(current.path), name = base(current.path) }
  end
  if not ignored then hidden, ignored = tree_config() end
  buf = joy.buffer.create({ unlisted = true })
  render(follow and follow.dir or joy.editor.get().cwd, follow and follow.name)
  local keys = {
    { "oil-open", "enter", open_entry, "Open the entry under the cursor" },
    { "oil-parent", "-", function() go(parent(view.dir)) end, "Go to the parent directory" },
    { "oil-hidden", "g .", function() hidden = not hidden; go(view.dir) end, "Show or hide dotfiles" },
    { "oil-close", "q", function() joy.editor.exec("tree-close") end, "Close the tree" },
  }
  for _, k in ipairs(keys) do
    joy.keymap.set(k[1], k[2], k[3], { when = "normal", buffer = buf, desc = k[4], no_wait = true })
  end
  local ok, err = pcall(joy.ui.mount, "oil-tree", tree, {
    replace = "file_tree", buffer = buf, fullscreen = true, keep_focus = true,
  })
  if not ok then joy.ui.notify("oil: " .. tostring(err), { level = "error" }) end
end

joy.on("ready", register)
joy.on("buffer_closed", function(ev)
  if ev.buffer == buf then register() end
end)

joy.keymap.set("oil", "-", function() joy.editor.exec("tree") end, {
  when = "normal", desc = "Show the file tree",
})
joy.command.set("Oil", function() joy.editor.exec("tree") end, { desc = "Show Oil, joy's file tree" })
joy.command.set("OilHidden", function()
  hidden = not hidden
  go(view.dir)
end, { desc = "Show or hide dotfiles in Oil" })
