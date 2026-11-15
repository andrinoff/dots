-- Icons for the "icon" column: Nerd Font glyphs, by name and extension.
-- joy's own file icons aren't reachable from Lua, so loam keeps a small
-- table of its own; setup({ icons = { lua = glyph, ["makefile"] = glyph } })
-- adds extensions and (lower-case) file names to it.

local M = {}

M.dir = ""
M.link = ""
M.file = ""

---@type table<string, string>
M.by_name = {
  ["makefile"] = "",
  ["dockerfile"] = "",
  ["license"] = "",
  [".gitignore"] = "",
  [".gitmodules"] = "",
  [".gitattributes"] = "",
  ["go.mod"] = "",
  ["go.sum"] = "",
}

---@type table<string, string>
M.by_ext = {
  go = "",
  lua = "",
  md = "",
  txt = "",
  json = "",
  toml = "",
  yaml = "",
  yml = "",
  js = "",
  mjs = "",
  ts = "",
  tsx = "",
  jsx = "",
  py = "",
  rs = "",
  rb = "",
  c = "",
  h = "",
  cpp = "",
  hpp = "",
  java = "",
  sh = "",
  zsh = "",
  bash = "",
  fish = "",
  html = "",
  css = "",
  scss = "",
  vim = "",
  sql = "",
  png = "",
  jpg = "",
  jpeg = "",
  gif = "",
  svg = "",
  pdf = "",
  zip = "",
  gz = "",
  tar = "",
  lock = "",
}

--- The glyph of an entry.
---@param name string
---@param typ string "file", "directory", "link"...
---@return string
function M.get(name, typ)
  if typ == "directory" then
    return M.dir
  end
  if typ == "link" then
    return M.link
  end
  local lower = name:lower()
  local by_name = M.by_name[lower]
  if by_name then
    return by_name
  end
  local ext = lower:match("%.([^.]+)$")
  return ext and M.by_ext[ext] or M.file
end

return M
