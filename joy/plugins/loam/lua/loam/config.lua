-- loam's options: the defaults, as oil.nvim's, and what setup() merged in.

local M = {}

---@alias loam.SortSpec [string, "asc"|"desc"]

---@class loam.ViewOptions
---@field show_hidden boolean Shows the files is_hidden_file hides.
---@field is_hidden_file fun(name: string, entry: loam.Entry?): boolean
---@field is_always_hidden fun(name: string, entry: loam.Entry?): boolean Never shown, not even with show_hidden.
---@field natural_order boolean Sorts "a2" before "a10".
---@field case_insensitive boolean Sorts names ignoring case.
---@field sort loam.SortSpec[] The columns to sort by, in order.

---@class loam.FloatOptions
---@field width number A fraction of the screen (<= 1) or columns.
---@field side "left"|"right"|"above"|"below" Where the window opens.

---@class loam.Keymap
---@field [1]? string|function An action's name ("actions.select") or a function.
---@field callback? string|function As [1].
---@field desc? string
---@field name? string Its name, which [keybinds] rebinds as loam.<name>: the action's ("select") by default.
---@field when? string When it works, as joy.keymap.set's when: "normal" by default.
---@field opts? table Given to the action.

---@class loam.Config
---@field default_file_explorer boolean Shows loam for a directory joy starts with (`joy .`).
---@field columns (string|table)[] "icon", "permissions", "size", "mtime".
---@field delete_to_trash boolean Deleted files go to the trash.
---@field skip_confirm_for_simple_edits boolean No confirmation for creates and renames within a directory.
---@field prompt_save_on_select_new_entry boolean Asks to save before opening an entry that isn't saved yet.
---@field constrain_cursor boolean Keeps the cursor off the hidden ids.
---@field global_keymap string|false The global key that opens the parent directory of the current file.
---@field view_options loam.ViewOptions
---@field float loam.FloatOptions
---@field use_default_keymaps boolean
---@field open_cmd? string[]|fun(path: string) What gx runs: `open` on macOS, `xdg-open` elsewhere.
---@field icons? table<string, string> More icons, by extension or lower-case file name.
---@field apply_on_write? boolean `:w` applies the edits (joy's auto-saves never do), unless false: then :LoamSave does.
---@field keymaps table<string, string|function|loam.Keymap|false> By joy's key names ("g s", "ctrl+p").

---@type loam.Config
M.defaults = {
  default_file_explorer = true,
  columns = { "icon" },
  delete_to_trash = false,
  skip_confirm_for_simple_edits = false,
  prompt_save_on_select_new_entry = true,
  constrain_cursor = true,
  global_keymap = "-",
  view_options = {
    show_hidden = false,
    is_hidden_file = function(name)
      return name:sub(1, 1) == "."
    end,
    is_always_hidden = function()
      return false
    end,
    natural_order = true,
    case_insensitive = false,
    sort = { { "type", "asc" }, { "name", "asc" } },
  },
  float = { width = 0.4, side = "left" },
  use_default_keymaps = true,
  keymaps = {
    ["g ?"] = "actions.show_help",
    ["enter"] = "actions.select",
    ["ctrl+s"] = { "actions.select", opts = { vertical = true }, desc = "Open the entry in a vertical split",
      name = "select-vertical" },
    ["ctrl+h"] = { "actions.select", opts = { horizontal = true }, desc = "Open the entry in a horizontal split",
      name = "select-horizontal" },
    ["ctrl+t"] = { "actions.select", opts = { tab = true }, desc = "Open the entry (joy has no tab pages: as enter)",
      name = "select-tab" },
    ["ctrl+p"] = "actions.preview",
    ["ctrl+c"] = "actions.close",
    ["ctrl+l"] = "actions.refresh",
    ["-"] = "actions.parent",
    ["_"] = "actions.open_cwd",
    ["`"] = "actions.cd",
    ["~"] = { "actions.cd", opts = { scope = "tab" }, desc = "cd to the directory (joy has one, for every tab)",
      name = "cd-tab" },
    ["g s"] = "actions.change_sort",
    ["g x"] = "actions.open_external",
    ["g ."] = "actions.toggle_hidden",
  },
}

--- Merges opts into the defaults, as setup() takes them: tables key by
--- key, lists replaced; the keymaps are the defaults' (unless
--- use_default_keymaps is false) and opts'.
---@param opts? table
---@return loam.Config
function M.build(opts)
  opts = opts or {}
  local cfg = joy.util.merge(M.defaults, opts)
  local keys = cfg.use_default_keymaps and joy.util.copy(M.defaults.keymaps) or {}
  for lhs, v in pairs(type(opts.keymaps) == "table" and opts.keymaps or {}) do
    keys[lhs] = joy.util.copy(v)
  end
  cfg.keymaps = keys
  return cfg
end

---@type loam.Config
M.options = M.build()

return M
