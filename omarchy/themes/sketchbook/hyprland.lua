-- Sketchbook: white pen on black paper.
-- The active window gets a stroke that fades as the pen lifts, and a hard
-- offset shadow, like a second line traced a little off the first.
local active_border = { colors = { "rgb(ffffff)", "rgb(8a8a8a)" }, angle = 45 }
local inactive_border = "rgb(262626)"

hl.config({
  general = {
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },

  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },

    groupbar = {
      font_family = "MonoLisa",
      font_weight_active = "bold",
      text_color = "rgb(ffffff)",
      text_color_inactive = "rgba(ffffff66)",
      col = {
        active = "rgba(ffffff1a)",
        inactive = "rgba(00000000)",
      },
    },
  },
})
