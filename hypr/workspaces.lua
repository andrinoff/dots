-- Plain Hyprland workspaces 1-10, each pinned to a monitor, replacing Omarchy's
-- per-monitor blocks. With an external monitor connected, 4-6 live on the
-- laptop panel and the rest on the external. Unplugged, Hyprland moves them all
-- to the panel under the same numbers; plugged back in, they return.

o = o or {}

local M = { slots = 10 }

local function monitors()
  local panel, external
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror then
      if monitor.name:match("^eDP") then
        panel = monitor
      else
        external = external or monitor
      end
    end
  end
  return panel, external
end

local function home(id)
  local panel, external = monitors()
  if id >= 4 and id <= 6 then
    return panel or external
  end
  return external or panel
end

local function pin()
  for id = 1, 10 do
    local monitor = home(id)
    if monitor then
      hl.workspace_rule({ workspace = tostring(id), monitor = monitor.name, persistent = id <= 6, default = id == 1 or id == 4 })
    end
  end
end

-- Put every numbered workspace back on its monitor.
function M.reconcile()
  pin()
  for _, workspace in ipairs(hl.get_workspaces()) do
    local monitor = workspace.id >= 1 and workspace.id <= 10 and home(workspace.id)
    if monitor and workspace.monitor and workspace.monitor.name ~= monitor.name then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace.id), monitor = monitor.name }))
    end
  end
end

local function action(fn, expression)
  o.bind_expressions = o.bind_expressions or {}
  o.bind_expressions[fn] = expression
  return fn
end

function M.workspace_id(_, slot)
  return slot
end

function M.focus(slot)
  return action(function()
    local monitor = home(slot)
    if monitor and not hl.get_workspace(slot) then
      hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
    end
    hl.dispatch(hl.dsp.focus({ workspace = tostring(slot) }))
  end, "o.workspaces.focus(" .. slot .. ")")
end

function M.move_window(slot, follow)
  return action(function()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(slot), follow = follow ~= false }))
  end, "o.workspaces.move_window(" .. slot .. (follow == false and ", false" or "") .. ")")
end

function M.move_to_monitor(direction)
  return action(function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
    end
  end, "o.workspaces.move_to_monitor(" .. string.format("%q", direction) .. ")")
end

function M.move_window_to_monitor(direction)
  return action(function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.window.move({ monitor = target.name }))
    end
  end, "o.workspaces.move_window_to_monitor(" .. string.format("%q", direction) .. ")")
end

-- Monitor settings are saved per physical monitor, by description.
function M.identities()
  local identities, taken = {}, {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror then
      local base = (monitor.description ~= nil and monitor.description ~= "") and monitor.description or monitor.name
      local identity, count = base, 1
      while taken[identity] do
        count = count + 1
        identity = base .. " #" .. count
      end
      identities[monitor.name], taken[identity] = identity, true
    end
  end
  return identities
end

pin()
hl.on("hyprland.start", M.reconcile)
hl.on("config.reloaded", M.reconcile)
hl.on("monitor.added", function()
  hl.timer(M.reconcile, { type = "oneshot", timeout = 100 })
end)
hl.on("monitor.removed", function()
  hl.timer(M.reconcile, { type = "oneshot", timeout = 100 })
end)

o.workspaces = M

return M
