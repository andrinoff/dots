-- clock: the time, as the "clock" item of the status bar.
-- Set format in config.toml's [plugins.clock.settings] to change it (an
-- os.date format, "%I:%M %p" by default); with seconds in it, it ticks
-- every second. icon is the Nerd Font glyph before it (nf-md-clock_outline).

local settings = joy.settings()
local format = settings.format or "%I:%M %p"
local icon = settings.icon or "󰥔"

local function tick()
  -- 12-hour time without the leading zero: "9:05 AM", not "09:05 AM".
  local time = tostring(os.date(format)):gsub("^0", "")
  joy.ui.set_status(icon .. " " .. time)
  -- Wait until the next second or minute starts, so it changes on time.
  local now = os.time()
  local wait = format:find("%%[ST]") and 1 or 60 - now % 60
  joy.timer.after(wait * 1000, tick)
end

tick()
