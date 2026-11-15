-- loam: edit the file system as a buffer, as oil.nvim does (lua/loam/).
--   :Loam [--float] [dir]   a directory in loam (the current file's by default)
--   :w in a loam buffer     applies the edits of every loam buffer, after asking
--   :LoamSave               the same, from anywhere
--   -                       the parent directory of the current file
--   require("loam").setup({ ... })   options: see lua/loam/config.lua

-- Defaults, unless the config called setup() first.
local loam = require("loam")
if not loam.did_setup then
  loam.setup()
end

joy.command.set("Loam", function(r)
  local float, dir = false, nil
  for _, a in ipairs(r.fields) do
    if a == "--float" then
      float = true
    else
      dir = a
    end
  end
  loam.open(dir, { float = float })
end, { complete = "dir", desc = "Edit a directory as a buffer" })

joy.command.set("LoamSave", function()
  loam.save()
end, { desc = "Apply the edits of the loam buffers" })

joy.on("ready", function()
  loam.on_startup()
end)
