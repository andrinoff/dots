-- Change the default Omarchy look'n'feel.

-- Cursor theme and size.
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "6")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "6")

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.

-- Sketchbook layout: windows sit on the page like cut paper, with the
-- drawing showing in the margins between them.
hl.config({
  general = {
    gaps_in = 6,
    gaps_out = { top = 8, right = 16, bottom = 16, left = 16 },
    border_size = 1,
  },

  decoration = {
    rounding = 0,

    -- Unfocused windows recede like pencil next to ink.
    dim_inactive = true,
    dim_strength = 0.12,
    dim_special = 0.4,

    -- Frosted paper behind see-through windows; the noise reads as grain.
    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      new_optimizations = true,
      xray = false,
      contrast = 1.0,
      brightness = 0.55,
      noise = 0.03,
      vibrancy = 0,
      popups = true,
      special = true,
    },
  },

  dwindle = {
    preserve_split = true,
    force_split = 2,
  },
})

-- Blur behind the shell's see-through cards (notifications, OSD, popovers); the
-- launcher and menus stay crisp.
hl.layer_rule({
  match = { namespace = "^(omarchy-notifications|omarchy-osd|omarchy-polkit|omarchy-clipboard|omarchy-emojis|omarchy-keyboard-panel)$" },
  blur = true,
  ignore_alpha = 0.3,
})

-- Motion: quick pen flicks with a hint of overshoot, nothing that waits on you.
hl.curve("pen", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("flick", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.04 } } })
hl.curve("lift", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.6, bezier = "flick", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.6, bezier = "lift", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.2, bezier = "pen", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "pen" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 4, bezier = "pen" })
hl.animation({ leaf = "workspaces", enabled = false })
hl.animation({ leaf = "workspacesIn", enabled = false })
hl.animation({ leaf = "workspacesOut", enabled = false })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.4, bezier = "pen", style = "slidefadevert 20%" })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })
