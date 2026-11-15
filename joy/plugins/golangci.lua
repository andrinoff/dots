-- golangci: runs golangci-lint on the module of a Go file when it's saved,
-- and puts its findings in the problems menu as diagnostics.
-- :GolangciLint runs it by hand; :GolangciLint off / on turns the saves off.

local opts = {
  cmd = { "golangci-lint", "run", "--output.json.path=stdout", "--output.text.path=",
    "--show-stats=false", "--max-issues-per-linter=0", "--max-same-issues=0" },
  target = "./...",   -- what to lint, from the module root
  load_files = true,  -- show issues of files that aren't open too
  timeout = 120000,   -- ms
}

local ns = "golangci" -- the diagnostics' namespace
local enabled = true
local running = {}  -- module root → its process
local pending = {}  -- module root → a save came in during a run
local tagged = {}   -- module root → the buffers it set diagnostics in

local severities = { error = "error", warning = "warning", info = "info", hint = "hint" }

-- root_of is the module root of a file: the directory of its go.mod.
local function root_of(path)
  return joy.fs.root(path, { "go.mod" })
end

-- buffer_of is the buffer of a file, loaded hidden and unlisted when it
-- isn't open and load_files is on: it stays out of the bufferline, :bn/:bp
-- and the buffer picker until you open the file.
local function buffer_of(file)
  for _, b in ipairs(joy.buffer.list()) do
    if b.path == file then return b.id end
  end
  if opts.load_files then return joy.buffer.open(file, { hidden = true, unlisted = true }) end
end

-- publish replaces the module's diagnostics with the issues of this run.
local function publish(root, issues)
  local by_file = {}
  for _, issue in ipairs(issues) do
    local pos = issue.Pos or {}
    local file = pos.Filename or ""
    if file ~= "" then
      if not file:match("^/") then file = joy.fs.join(root, file) end
      local list = by_file[file] or {}
      by_file[file] = list
      local row = math.max((pos.Line or 1) - 1, 0)
      local col = math.max((pos.Column or 1) - 1, 0)
      list[#list + 1] = {
        row = row, col = col, end_row = row, end_col = col,
        severity = severities[(issue.Severity or ""):lower()] or "warning",
        message = issue.Text or "",
        source = "golangci-lint: " .. (issue.FromLinter or "?"),
      }
    end
  end

  -- Clear the buffers of the last run that have nothing now.
  for buf in pairs(tagged[root] or {}) do
    local b = joy.buffer.get(buf)
    if b and not by_file[b.path] then joy.buffer.set_diagnostics(buf, ns, {}) end
  end
  tagged[root] = {}

  for file, items in pairs(by_file) do
    local buf = buffer_of(file)
    if buf then
      joy.buffer.set_diagnostics(buf, ns, items)
      tagged[root][buf] = true
    end
  end
end

local run

-- finish handles a run's result: JSON on stdout, exit 0 or 1 (issues found).
local function finish(root, result)
  running[root] = nil
  local out = result.stdout or ""
  local json = out:match("^%s*({.*})%s*$") or out:match("({\"Issues\".*})")
  local ok, data = pcall(joy.json.decode, json or "")
  if not ok or type(data) ~= "table" then
    if not result.timed_out then
      local err = (result.stderr or ""):gsub("%s+$", "")
      joy.ui.notify("golangci-lint failed (" .. result.code .. "): " .. (err ~= "" and err or "no output"),
        { level = "error" })
    end
  else
    publish(root, data.Issues or {})
  end
  if pending[root] then
    pending[root] = nil
    run(root)
  end
end

run = function(root)
  if running[root] then
    pending[root] = true -- one more run once this one is done
    return
  end
  local cmd = { unpack(opts.cmd) }
  cmd[#cmd + 1] = opts.target
  -- The exit function runs as a task on joy's loop, as event handlers do.
  local proc, err = joy.process.start(cmd, { cwd = root, timeout = opts.timeout }, function(result)
    finish(root, result)
  end)
  if not proc then
    joy.ui.notify("golangci-lint didn't start: " .. tostring(err), { level = "error" })
    return
  end
  running[root] = proc
end

joy.on("buffer_saved", function(e)
  if not enabled or not e.path:match("%.go$") then return end
  local root = root_of(e.path)
  if root then run(root) end
end)

joy.command.set("GolangciLint", function(r)
  local arg = r.args
  if arg == "off" or arg == "on" then
    enabled = arg == "on"
    if not enabled then -- clear every buffer it set diagnostics in
      for _, bufs in pairs(tagged) do
        for buf in pairs(bufs) do joy.buffer.set_diagnostics(buf, ns, {}) end
      end
    end
    joy.ui.notify("golangci-lint on save " .. (enabled and "on" or "off"))
    return
  end
  local b = joy.buffer.get(0)
  local root = b and b.path ~= "" and root_of(b.path)
  if not root then
    joy.ui.notify("No go.mod above this buffer", { level = "warning" })
    return
  end
  run(root)
end, {
  desc = "Run golangci-lint on the module; off / on turns it off on save",
  choices = { "on", "off" },
})
