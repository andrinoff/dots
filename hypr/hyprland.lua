-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false
--
-- Disable Omarchy's default touchpad gestures. Add your own in hypr/input.lua.
-- omarchy_default_gestures = false

-- Load Omarchy defaults with SUPER and ALT swapped, so ALT is the main mod.
-- Copy, paste, cut and select all stay on SUPER.
local bind = hl.bind
hl.bind = function(keys, ...)
  if not keys:match("^SUPER %+ [ACVX]$") then
    keys = keys:gsub("%f[%w_]SUPER%f[^%w_]", "@MOD@"):gsub("%f[%w_]ALT%f[^%w_]", "SUPER"):gsub("@MOD@", "ALT")
  end
  return bind(keys, ...)
end
require("default.hypr.helpers")
package.loaded["default.hypr.monitor-workspaces"] = require("hypr.workspaces")
require("default.hypr.omarchy")
hl.bind = bind

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
