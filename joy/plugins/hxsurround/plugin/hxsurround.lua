-- hxsurround: surrounds for joy's Helix mode, beside its own m s / m r / m d
-- (single characters and bracket pairs), under the capital keys of the
-- same m menu, in normal and select mode:
--   m S <key>  wrap the selection: t <tag>, f fn(…), c custom, * ** _ ` ~~,
--              brackets and quotes, and keys of setup({ surrounds = … })
--   m D <key>  delete the nearest enclosing tag, call, markdown marker, custom
--   m R <key>  change the enclosing tag (t) or function name (f)
-- The work lives in lua/hxsurround/*.lua, loaded on first use.

-- run calls an action of the module, loading it the first time.
local function run(action, key)
  return function() require("hxsurround")[action](key) end
end

-- map sets keys in Helix's normal and select modes. The key hints show a
-- keymap's name, so the name says what it does: m S * is wrap-bold.
local function map(prefix, action, key, name, desc)
  joy.keymap.set(name, prefix .. " " .. key, run(action, key), { when = "normal select", desc = desc })
end

local adds = {
  { "t", "tag", "<tag>…</tag>" }, { "f", "call", "fn(…)" }, { "c", "custom", "a custom open/close" },
  { "*", "bold", "**bold**" }, { "_", "italic", "_italic_" }, { "`", "code", "`code` or a fence" },
  { "~", "strike", "~~strike~~" },
  { "(", "paren", "( )" }, { ")", "paren", "( )" }, { "[", "bracket", "[ ]" }, { "]", "bracket", "[ ]" },
  { "{", "brace", "{ }" }, { "}", "brace", "{ }" }, { "<", "angle", "< >" }, { ">", "angle", "< >" },
  { '"', "dquote", '" "' }, { "'", "squote", "' '" },
}
local closing = { [")"] = true, ["]"] = true, ["}"] = true, [">"] = true }
for _, a in ipairs(adds) do
  map("m S", "add", a[1], "wrap-" .. a[2] .. (closing[a[1]] and "-close" or ""), "Wrap in " .. a[3])
end
for i = 1, 7 do -- the deletes of the keys before the brackets
  local a = adds[i]
  map("m D", "delete", a[1], "delete-" .. a[2], "Delete the " .. a[3] .. " around")
end
map("m R", "change", "t", "change-tag", "Change the <tag> around")
map("m R", "change", "f", "rename-call", "Rename the fn(…) around")
