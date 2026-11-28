-- Keep only your personal keybinding overrides here. Add new bindings with
-- o.bind or replace defaults with o.rebind.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable only the preinstalled app/webapp bindings, set this in the same
-- place in ~/.config/hypr/hyprland.lua:
--   omarchy_preinstalled_bindings = false

-- Add a new binding. xdg-terminal-exec opens the default terminal.
-- o.bind("SUPER + SHIFT + R", "SSH", "xdg-terminal-exec -e ssh your-server")

-- Change an existing binding. o.rebind takes the same arguments as o.bind.
-- This example replaces the default file manager with Flea.
-- o.rebind("SUPER + SHIFT + F", "File manager", { launch = "flea" })

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, { panel = "omarchy.emojis" })

-- Focus and swap windows with Alt + dhtn (QWERTY hjkl positions), staying on the current monitor.
-- Alt + arrows (and Shift) are left to apps for text navigation.
for _, arrow in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
  hl.unbind("ALT + " .. arrow)
  hl.unbind("ALT + SHIFT + " .. arrow)
end
for key, dir in pairs({ D = "l", H = "d", T = "u", N = "r" }) do
  o.rebind("ALT + " .. key, "Focus window " .. dir, hl.dsp.focus({ direction = dir }))
  o.rebind("ALT + SHIFT + " .. key, "Swap window " .. dir, hl.dsp.window.swap({ direction = dir }))
end
hl.config({ binds = { window_direction_monitor_fallback = false } })

-- Alt + Backspace deletes a word backward (replaces transparency toggle).
local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end
  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

local function send_key(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 20, type = "oneshot" })
end

o.rebind("ALT + BACKSPACE", "Delete word backward", function()
  send_key(active_window_is_terminal() and "ALT" or "CTRL", "BackSpace")
end, { repeating = true })

for _, dir in ipairs({ { bind = "LEFT", key = "Left", label = "backward" }, { bind = "RIGHT", key = "Right", label = "forward" } }) do
  o.bind("ALT + " .. dir.bind, "Word " .. dir.label, function()
    send_key(active_window_is_terminal() and "ALT" or "CTRL", dir.key)
  end, { repeating = true })
  o.bind("ALT + SHIFT + " .. dir.bind, "Select word " .. dir.label, function()
    send_key(active_window_is_terminal() and "ALT SHIFT" or "CTRL SHIFT", dir.key)
  end, { repeating = true })
end

o.bind("SUPER + W", "Close window", hl.dsp.window.close())

-- Alt + M drops down matcha in Ghostty. It lives on its own special workspace,
-- started the first time the dropdown opens (and again after matcha quits).
local MATCHA = "special:matcha"
hl.on("workspace.created", function(ws)
  if ws and ws.name == MATCHA and ws.is_empty then
    hl.exec_cmd("uwsm-app -- ghostty --class=org.omarchy.matcha -e " .. os.getenv("HOME") .. "/go/bin/matcha", { workspace = MATCHA .. " silent" })
  end
end)
o.window("org\\.omarchy\\.matcha", {
  float = true,
  size = "monitor_w*0.7 monitor_h*0.6",
  move = "monitor_w*0.15 monitor_h*0.04",
})
o.rebind("ALT + M", "Matcha dropdown", hl.dsp.workspace.toggle_special("matcha"))
