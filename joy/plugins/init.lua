joy.pack.load("todo")
joy.pack.load("colors")
joy.pack.load("snippets")
joy.pack.load("marks") -- harpoon: space a adds, space m picks, alt+1..4 jump
for i = 1, 4 do
  -- The keys fed reach keymaps: marks' alt+i runs.
  joy.keymap.set("mark-" .. i, "ctrl+" .. i, function() joy.editor.feed_keys("alt+" .. i) end,
    { desc = "Go to mark " .. i })
end
