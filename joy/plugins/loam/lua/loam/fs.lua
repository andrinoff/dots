-- loam's file system work: paths, listing a directory, and the operations
-- a save applies (each returns true, or nil and an error).

local M = {}

---@class loam.FsEntry
---@field name string
---@field type "file"|"directory"|"link"|string
---@field link? string A link's target, as written.
---@field link_type? string What a link points to, links followed; nil when it is broken.
---@field mode? integer
---@field size? integer
---@field mtime? number

M.is_windows = package.config:sub(1, 1) == "\\"

--- An absolute, clean path, without a trailing slash (but "/").
---@param path string
---@return string
function M.normalize(path)
  return joy.fs.abspath(path)
end

---@param dir string
---@param name string
---@return string
function M.join(dir, name)
  if dir == "/" then
    return "/" .. name
  end
  return dir .. "/" .. name
end

--- The directory a path is in ("/" for "/").
---@param path string
---@return string
function M.parent(path)
  if path == "/" then
    return "/"
  end
  local p = path:match("^(.*)/[^/]*$")
  if p == nil or p == "" then
    return "/"
  end
  return p
end

---@param path string
---@return string
function M.basename(path)
  return path:match("([^/]*)$") or path
end

--- Whether `path` is `dir` or inside it.
---@param path string
---@param dir string
---@return boolean
function M.is_under(path, dir)
  if path == dir then
    return true
  end
  if dir == "/" then
    return path:sub(1, 1) == "/"
  end
  return path:sub(1, #dir + 1) == dir .. "/"
end

--- The type of whatever is at path, links not followed; nil when nothing is.
---@param path string
---@return string?
function M.ltype(path)
  local st = joy.fs.stat(path)
  return st and st.type or nil
end

---@param path string
---@return boolean
function M.exists(path)
  return joy.fs.exists(path)
end

--- Whether path is a directory, or a link to one.
---@param path string
---@return boolean
function M.is_dir(path)
  local st = joy.fs.stat(path)
  return st ~= nil and (st.type == "directory" or st.type == "link" and st.target_type == "directory")
end

--- The entries of a directory.
---@param dir string
---@return loam.FsEntry[]? entries
---@return string? err
function M.list(dir)
  local entries, err = joy.fs.list(dir)
  if not entries then
    return nil, err
  end
  local out = {}
  for _, fe in ipairs(entries) do
    local e = { name = fe.name, type = fe.type }
    local st = joy.fs.stat(M.join(dir, fe.name))
    if st then
      e.type = st.type
      e.mode, e.size, e.mtime = st.mode, st.size, st.mtime
      if st.type == "link" then
        e.link = st.target
        e.link_type = st.target_type ~= "" and st.target_type or nil
      end
    end
    out[#out + 1] = e
  end
  return out
end

--- Makes a directory and the ones it is in.
---@param path string
---@return true? ok
---@return string? err
function M.mkdirp(path)
  return joy.fs.mkdir(path)
end

--- Removes a file, a link or a directory and what it holds, links never
--- followed.
---@param path string
---@return true? ok
---@return string? err
function M.remove(path)
  if not M.exists(path) then
    return nil, "no such file: " .. path
  end
  return joy.fs.remove(path, { recursive = true })
end

--- Copies a file, a link (as a link) or a directory and what it holds,
--- with their permissions, to a path where nothing is.
---@param src string
---@param dest string
---@return true? ok
---@return string? err
function M.copy(src, dest)
  local st, err = joy.fs.stat(src)
  if not st then
    return nil, err
  end
  if M.exists(dest) then
    return nil, dest .. " exists already"
  end
  if st.type == "link" then
    return joy.fs.symlink(st.target, dest)
  end
  if st.type == "directory" then
    local ok, err2 = joy.fs.mkdir(dest)
    if not ok then
      return nil, err2
    end
    local entries, err3 = joy.fs.list(src)
    if not entries then
      return nil, err3
    end
    for _, e in ipairs(entries) do
      local ok2, err4 = M.copy(M.join(src, e.name), M.join(dest, e.name))
      if not ok2 then
        return nil, err4
      end
    end
    return joy.fs.chmod(dest, st.mode)
  end
  local ok, err2 = joy.fs.copy(src, dest)
  if not ok then
    return nil, err2
  end
  return joy.fs.chmod(dest, st.mode)
end

--- Moves a file or a directory, copying it when it goes to another file
--- system.
---@param src string
---@param dest string
---@return true? ok
---@return string? err
function M.move(src, dest)
  local ok, err = joy.fs.rename(src, dest)
  if ok then
    return true
  end
  if err and err:find("cross%-device") then
    local copied, err2 = M.copy(src, dest)
    if not copied then
      return nil, err2
    end
    return M.remove(src)
  end
  return nil, err
end

--- A name next to `path` that nothing has.
---@param dir string
---@param name string
---@return string
function M.unique(dir, name)
  local path = M.join(dir, name)
  local i = 1
  while M.exists(path) do
    i = i + 1
    local stem, ext = name:match("^(.+)(%.[^.]+)$")
    if stem then
      path = M.join(dir, stem .. " " .. i .. ext)
    else
      path = M.join(dir, name .. " " .. i)
    end
  end
  return path
end

--- Puts a file in the trash: macOS's ~/.Trash, or the freedesktop trash.
---@param path string
---@return true? ok
---@return string? err
function M.trash(path)
  local home = os.getenv("HOME") or "/"
  local name = M.basename(path)
  if joy.util.os() == "darwin" then
    local trash = M.join(home, ".Trash")
    local ok, err = M.mkdirp(trash)
    if not ok then
      return nil, err
    end
    return M.move(path, M.unique(trash, name))
  end
  local base = os.getenv("XDG_DATA_HOME")
  if base == nil or base == "" then
    base = M.join(home, ".local/share")
  end
  local files, info = M.join(base, "Trash/files"), M.join(base, "Trash/info")
  local ok, err = M.mkdirp(files)
  if not ok then
    return nil, err
  end
  ok, err = M.mkdirp(info)
  if not ok then
    return nil, err
  end
  local dest = M.unique(files, name)
  local stamp = os.date("%Y-%m-%dT%H:%M:%S")
  local written, err2 = joy.fs.write(M.join(info, M.basename(dest) .. ".trashinfo"),
    "[Trash Info]\nPath=" .. path .. "\nDeletionDate=" .. tostring(stamp) .. "\n")
  if not written then
    return nil, err2
  end
  return M.move(path, dest)
end

--- A permission string, as ls writes it: "drwxr-xr-x".
---@param typ string
---@param mode? integer
---@return string
function M.permissions(typ, mode)
  local first = typ == "directory" and "d" or typ == "link" and "l" or "-"
  if not mode then
    return first .. "?????????"
  end
  local bits = "rwxrwxrwx"
  local out = { first }
  for i = 8, 0, -1 do
    local on = math.floor(mode / 2 ^ i) % 2 == 1
    local pos = 9 - i
    out[#out + 1] = on and bits:sub(pos, pos) or "-"
  end
  return table.concat(out)
end

--- A size for people: "512", "4.1k", "12M".
---@param size? integer
---@return string
function M.human_size(size)
  if not size then
    return "-"
  end
  local units = { "", "k", "M", "G", "T" }
  local n, i = size, 1
  while n >= 1024 and i < #units do
    n = n / 1024
    i = i + 1
  end
  if i == 1 then
    return tostring(n)
  end
  if n < 10 then
    return string.format("%.1f%s", n, units[i])
  end
  return string.format("%d%s", math.floor(n + 0.5), units[i])
end

return M
