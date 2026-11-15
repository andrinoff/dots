-- loam's keymaps: the buffer's (config.keymaps) and the global one.

local config = require("loam.config")

local M = {}

---@type table<integer, string[]> The names of each buffer's keymaps.
local set_on = {}

--- An action's function, description, name and condition, from a
--- keymap's value.
---@param lhs string
---@param value string|function|loam.Keymap
---@return function? fn
---@return string? desc
---@return string name
---@return string when
local function resolve(lhs, value)
  local when = "normal"
  local opts, desc, name
  local action = value ---@type string|function|loam.Keymap|nil
  if type(value) == "table" then
    action = value.callback or value[1]
    opts, desc, name = value.opts, value.desc, value.name
    when = value.when or when
  end
  if type(action) == "function" then
    local fn = action
    return function()
      fn(opts)
    end, desc or "loam keymap", name or (lhs:gsub(" ", "-")), when
  end
  if type(action) == "string" then
    local key = action:gsub("^actions%.", "")
    local actions = require("loam.actions")
    local fn = actions[key]
    if type(fn) ~= "function" then
      joy.ui.notify("loam: no action " .. action, { level = "warning" })
      return nil, nil, "", when
    end
    return function()
      fn(opts)
    end, desc or actions.descriptions[key] or key, name or (key:gsub("_", "-")), when
  end
  return nil, nil, "", when
end

--- Sets the keymaps of a loam buffer, again after setup().
---@param buf integer
function M.set_buffer(buf)
  for _, name in ipairs(set_on[buf] or {}) do
    joy.keymap.delete(name, { buffer = buf })
  end
  local lhss = {}
  for lhs in pairs(config.options.keymaps) do
    lhss[#lhss + 1] = lhs
  end
  table.sort(lhss) -- the same names each time
  local names, taken = {}, {}
  for _, lhs in ipairs(lhss) do
    local value = config.options.keymaps[lhs]
    if value then
      local fn, desc, name, when = resolve(lhs, value)
      if fn then
        local unique, n = name, 1
        while taken[unique] do -- two keys of one action: select, select-2
          n = n + 1
          unique = name .. "-" .. n
        end
        taken[unique] = true
        joy.keymap.set(unique, lhs, fn, { buffer = buf, desc = desc, when = when, no_wait = true })
        names[#names + 1] = unique
      end
    end
  end
  set_on[buf] = names
end

--- The keymaps a loam buffer has, for the help: { lhs, desc }, sorted.
---@return {[1]: string, [2]: string}[]
function M.list()
  local out = {}
  for lhs, value in pairs(config.options.keymaps) do
    if value then
      local fn, desc = resolve(lhs, value)
      if fn then
        out[#out + 1] = { lhs, desc or "" }
      end
    end
  end
  table.sort(out, function(a, b)
    return a[1] < b[1]
  end)
  return out
end

--- Sets the global key that opens the parent directory (`-`).
function M.set_global()
  local keys = config.options.global_keymap
  if not keys then
    joy.keymap.delete("open-parent") -- set before, or nothing
    return
  end
  joy.keymap.set("open-parent", keys, function()
    require("loam").open_parent()
  end, { when = "normal", desc = "Open the parent directory" })
end

return M
