-- Saving: the actions the loam buffers' edits stand for, checked, shown,
-- and applied in an order that works.

local config = require("loam.config")
local fs = require("loam.fs")
local view = require("loam.view")

local M = {}

---@class loam.Action
---@field type "create"|"delete"|"move"|"copy"
---@field entry_type string "file", "directory" or "link".
---@field src? string The path moved, copied or deleted.
---@field dest? string The path made.
---@field link? string A new link's target.
---@field noop? boolean A directory to create that is there already.

--- A path inside directory `from` (not `from` itself), inside `to` instead.
---@param path string
---@param from string
---@param to string
---@return string
local function rebase(path, from, to)
  if path ~= from and fs.is_under(path, from) then
    return to .. path:sub(#from + 1)
  end
  return path
end

--- Checks a name typed in a line.
---@param name string
---@return string? err
local function check_name(name)
  if name == "" then
    return "an empty name"
  end
  if name:sub(1, 1) == "/" then
    return "an absolute path: " .. name
  end
  local parts = name .. "/"
  for part in parts:gmatch("([^/]*)/") do
    if part == "" then
      return "an empty part in " .. name
    end
    if part == "." or part == ".." then
      return "'" .. part .. "' in " .. name
    end
  end
  return nil
end

--- The actions the edits of every loam buffer stand for, or the errors
--- that stop the save.
---@return loam.Action[] actions
---@return string[] errors
function M.compute()
  local actions, errors = {}, {}
  local dests = {} ---@type table<integer, {path: string, row: integer, dir: string}[]>
  local kept = {} ---@type table<integer, boolean>
  local seen_ids = {} ---@type table<integer, boolean>
  local order = {} ---@type integer[]
  local bufs = {}
  for buf in pairs(view.bufs) do
    if joy.buffer.get(buf) then
      bufs[#bufs + 1] = buf
    else
      view.bufs[buf] = nil
    end
  end
  table.sort(bufs)
  for _, buf in ipairs(bufs) do
    local st = view.bufs[buf]
    local names = {} ---@type table<string, integer>
    for row, line in ipairs(joy.buffer.get_lines(buf, 0, -1) or {}) do
      local p = view.parse_line(line, row)
      if p then
        local where = st.dir .. "/ line " .. row
        local err = check_name(p.name)
        if err then
          errors[#errors + 1] = where .. ": " .. err
        else
          local dest = fs.join(st.dir, p.name)
          local key = dest:lower()
          if names[key] then
            errors[#errors + 1] = where .. ": " .. p.name .. " is also on line " .. names[key]
          end
          names[key] = row
          if p.entry then
            local e = p.entry ---@type loam.Entry
            if not seen_ids[e.id] then
              seen_ids[e.id] = true
              order[#order + 1] = e.id
            end
            if e.dir == st.dir and p.name == e.name then
              kept[e.id] = true
            else
              dests[e.id] = dests[e.id] or {}
              table.insert(dests[e.id], { path = dest, row = row, dir = st.dir })
            end
          else
            actions[#actions + 1] = {
              type = "create",
              dest = dest,
              entry_type = p.link and "link" or (p.is_dir and "directory" or "file"),
              link = p.link,
            }
          end
        end
      end
    end
  end
  -- Entries rendered in a buffer but on no line of any: deleted.
  for _, buf in ipairs(bufs) do
    for _, id in ipairs(view.bufs[buf].ids) do
      if not seen_ids[id] and view.entries[id] then
        seen_ids[id] = true
        order[#order + 1] = id
      end
    end
  end
  for _, id in ipairs(order) do
    local e = view.entries[id]
    local src = fs.join(e.dir, e.name)
    local list = dests[id] or {}
    local source_buf = view.dir_bufs[e.dir]
    local source_shown = source_buf ~= nil and view.bufs[source_buf] ~= nil
    -- Without the source's buffer, nothing says it went: a copy.
    local original_stays = kept[id] or not source_shown
    if original_stays then
      for _, d in ipairs(list) do
        actions[#actions + 1] = { type = "copy", src = src, dest = d.path, entry_type = e.type }
      end
    elseif #list == 0 then
      actions[#actions + 1] = { type = "delete", src = src, entry_type = e.type }
    else
      actions[#actions + 1] = { type = "move", src = src, dest = list[1].path, entry_type = e.type }
      for i = 2, #list do
        actions[#actions + 1] = { type = "copy", src = src, dest = list[i].path, entry_type = e.type }
      end
    end
  end
  if #errors == 0 then
    M.check(actions, errors)
  end
  return M.sorted(actions), errors
end

--- Adds the errors of actions that can't work: a source that is gone, a
--- destination that is there and stays, the same destination twice.
---@param actions loam.Action[]
---@param errors string[]
function M.check(actions, errors)
  local vacated = {} ---@type string[]
  for _, a in ipairs(actions) do
    if a.type == "move" or a.type == "delete" then
      vacated[#vacated + 1] = a.src
    end
  end
  local function leaves(path)
    for _, v in ipairs(vacated) do
      if fs.is_under(path, v) or path:lower() == v:lower() then
        return true
      end
    end
    return false
  end
  local targets = {}
  for _, a in ipairs(actions) do
    if a.src and not fs.exists(a.src) then
      errors[#errors + 1] = fs.basename(a.src) .. " isn't there any more"
    end
    if a.dest then
      if targets[a.dest] then
        errors[#errors + 1] = a.dest .. " would be made twice"
      end
      targets[a.dest] = true
      if a.type == "create" and a.entry_type == "directory" and fs.is_dir(a.dest) then
        a.noop = true
      elseif fs.exists(a.dest) and not leaves(a.dest) then
        errors[#errors + 1] = a.dest .. " exists already"
      end
    end
  end
end

local rank = { create = 1, copy = 2, move = 3, delete = 4 }

--- Actions in the order they are shown: creates, copies, moves, deletes.
---@param actions loam.Action[]
---@return loam.Action[]
function M.sorted(actions)
  local out = {}
  for i, a in ipairs(actions) do
    out[i] = a
  end
  table.sort(out, function(a, b)
    if rank[a.type] ~= rank[b.type] then
      return rank[a.type] < rank[b.type]
    end
    local x, y = a.src or a.dest or "", b.src or b.dest or ""
    if x ~= y then
      return x < y
    end
    return (a.dest or "") < (b.dest or "")
  end)
  return out
end

--- A path as the confirmation shows it: from the current directory, or
--- from ~.
---@param path string
---@return string
function M.display(path)
  local cwd = fs.normalize(joy.editor.get().cwd)
  if cwd ~= "/" and fs.is_under(path, cwd) and path ~= cwd then
    return path:sub(#cwd + 2)
  end
  local home = os.getenv("HOME")
  if home and fs.is_under(path, home) then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

--- The lines of the confirmation, oil's way: "CREATE a/b.txt".
---@param actions loam.Action[]
---@return string[]
function M.describe(actions)
  local out = {}
  for _, a in ipairs(actions) do
    local slash = a.entry_type == "directory" and "/" or ""
    if a.type == "create" then
      local link = a.link and (" -> " .. a.link) or ""
      out[#out + 1] = "CREATE " .. M.display(a.dest) .. slash .. link
    elseif a.type == "delete" then
      out[#out + 1] = "DELETE " .. M.display(a.src) .. slash
    elseif a.type == "move" then
      out[#out + 1] = "  MOVE " .. M.display(a.src) .. slash .. " -> " .. M.display(a.dest) .. slash
    else
      out[#out + 1] = "  COPY " .. M.display(a.src) .. slash .. " -> " .. M.display(a.dest) .. slash
    end
  end
  return out
end

--- Whether the confirmation can be skipped: no deletes, and moves and
--- copies within one directory (renames).
---@param actions loam.Action[]
---@return boolean
function M.is_simple(actions)
  for _, a in ipairs(actions) do
    if a.type == "delete" then
      return false
    end
    if (a.type == "move" or a.type == "copy") and fs.parent(a.src) ~= fs.parent(a.dest) then
      return false
    end
  end
  return true
end

--- A free name beside path, for a move that has to wait.
---@param path string
---@return string
local function temp_beside(path)
  repeat
    -- tempname's name is random: no other joy picks it too.
    path = fs.join(fs.parent(path), ".loam-" .. fs.basename(joy.fs.tempname()) .. "~")
  until not fs.exists(path)
  return path
end

--- Does one action.
---@param a loam.Action
---@return true? ok
---@return string? err
local function run(a)
  if a.noop then
    return true
  end
  if a.dest then
    local ok, err = fs.mkdirp(fs.parent(a.dest))
    if not ok then
      return nil, err
    end
  end
  if a.type == "create" then
    if a.entry_type == "directory" then
      if fs.is_dir(a.dest) then
        return true
      end
      return fs.mkdirp(a.dest)
    elseif a.entry_type == "link" then
      return joy.fs.symlink(a.link or "", a.dest)
    end
    return joy.fs.write(a.dest, "")
  elseif a.type == "copy" then
    return fs.copy(a.src, a.dest)
  elseif a.type == "move" then
    return fs.move(a.src, a.dest)
  end
  if config.options.delete_to_trash then
    return fs.trash(a.src)
  end
  return fs.remove(a.src)
end

--- Applies the actions; it stops at the first that fails.
---
--- Copies go first, while every source is as it was (to a temporary name
--- when their destination is still taken). Then whatever is ready runs: a
--- move or a create when its destination is free, a delete when nothing
--- left to do comes out of it. When nothing is ready, moves wait for each
--- other (a swap): one moves aside to a temporary name. A directory that
--- moves takes the paths of the actions below it along.
---@param actions loam.Action[]
---@return string? err
function M.apply(actions)
  local pending = {} ---@type loam.Action[]
  for _, a in ipairs(actions) do
    if a.type == "copy" then
      if fs.exists(a.dest) then
        local tmp = temp_beside(a.src)
        local ok, err = fs.copy(a.src, tmp)
        if not ok then
          return "COPY " .. a.src .. ": " .. tostring(err)
        end
        pending[#pending + 1] = { type = "move", src = tmp, dest = a.dest, entry_type = a.entry_type }
      else
        local ok, err = run(a)
        if not ok then
          return "COPY " .. a.src .. " -> " .. a.dest .. ": " .. tostring(err)
        end
      end
    else
      pending[#pending + 1] = a
    end
  end
  local function ready(a)
    if a.type == "delete" then
      for _, b in ipairs(pending) do
        if b ~= a and b.type == "move" and fs.is_under(b.src, a.src) then
          return false
        end
      end
      return true
    end
    if a.noop then
      return true
    end
    if a.type == "create" and a.entry_type == "directory" and fs.is_dir(a.dest) then
      return true
    end
    return not fs.exists(a.dest)
  end
  local rounds = 0
  while #pending > 0 do
    rounds = rounds + 1
    if rounds > 4 * (#actions + 2) then
      return "can't find an order for the changes left: " .. (pending[1].dest or pending[1].src or "?")
    end
    local done = nil
    for i, a in ipairs(pending) do
      if ready(a) then
        done = i
        break
      end
    end
    if done then
      local a = table.remove(pending, done)
      local ok, err = run(a)
      if not ok then
        return string.upper(a.type) .. " " .. (a.src or a.dest or "") .. ": " .. tostring(err)
      end
      if a.type == "move" then
        for _, b in ipairs(pending) do
          if b.src then
            b.src = rebase(b.src, a.src, a.dest)
          end
          if b.dest then
            b.dest = rebase(b.dest, a.src, a.dest)
          end
        end
      end
    else
      local stuck = nil
      for _, a in ipairs(pending) do
        if a.type == "move" then
          stuck = a
          break
        end
      end
      if not stuck then
        local a = pending[1]
        return (a.dest or a.src or "?") .. " is in the way"
      end
      local tmp = temp_beside(stuck.src)
      local ok, err = fs.move(stuck.src, tmp)
      if not ok then
        return "MOVE " .. stuck.src .. ": " .. tostring(err)
      end
      local from = stuck.src
      stuck.src = tmp
      for _, b in ipairs(pending) do
        if b.src then
          b.src = rebase(b.src, from, tmp)
        end
      end
    end
  end
  return nil
end

return M
