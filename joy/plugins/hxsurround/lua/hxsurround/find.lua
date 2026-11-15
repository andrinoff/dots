-- hxsurround.find: the nearest pair enclosing a selection. Texts are a
-- buffer's lines joined by "\n"; offsets are 0-based bytes, ends exclusive.
-- A match is { os, oe, cs, ce }: the open at [os, oe), the close at [cs, ce).
local M = {}

---@class hxsurround.Match
---@field os integer
---@field oe integer
---@field cs integer
---@field ce integer
---@field name? string A tag's or a call's name, as written.
---@field attrs? string A tag's attributes, with the space before them.

-- keep takes m over best when m encloses [s, e) and is nearer (smaller).
local function keep(best, m, s, e)
  if m.os <= s and e <= m.ce and (not best or m.ce - m.os < best.ce - best.os) then return m end
  return best
end

-- tag_end is the index of the ">" ending a tag from j, past quoted values;
-- nil when a "<" comes first (a stray "<", not a tag).
local function tag_end(text, j)
  local q
  for k = j, #text do
    local c = text:sub(k, k)
    if q then
      if c == q then q = nil end
    elseif c == '"' or c == "'" then
      q = c
    elseif c == ">" then
      return k
    elseif c == "<" then
      return nil
    end
  end
end

--- The nearest HTML/XML element around [s, e): nesting, attributes,
--- self-closing tags and comments handled; tag names match ignoring case.
---@param text string
---@param s integer
---@param e integer
---@return hxsurround.Match?
function M.tag(text, s, e)
  local stack, best, i = {}, nil, 1
  while true do
    local lt = text:find("<", i, true)
    if not lt then break end
    i = lt + 1
    if text:sub(lt, lt + 3) == "<!--" then
      local c = text:find("-->", lt + 4, true)
      i = c and c + 3 or #text + 1
    else
      local slash, name = text:match("^<(/?)([%a_][%w:_%.%-]*)", lt)
      local gt = name and tag_end(text, lt + 1 + #slash + #name)
      if gt then
        i = gt + 1
        local t = { s = lt - 1, e = gt, name = name, key = name:lower(),
          attrs = text:sub(lt + 1 + #name, gt - 1) }
        if slash == "/" then
          for k = #stack, 1, -1 do -- close the nearest open of that name
            if stack[k].key == t.key then
              local o = stack[k]
              for _ = k, #stack do table.remove(stack) end
              best = keep(best, { os = o.s, oe = o.e, cs = t.s, ce = t.e, name = o.name, attrs = o.attrs }, s, e)
              break
            end
          end
        elseif text:sub(gt - 1, gt - 1) ~= "/" then
          stack[#stack + 1] = t
        end
      end
    end
  end
  return best
end

local keywords = {}
for w in ("if for while switch return func function catch elseif elif and or not in"):gmatch("%S+") do
  keywords[w] = true
end

-- skip_string is the index of the quote closing the string opened at i on
-- its line, or i when it isn't one (an apostrophe, an unclosed quote).
local function skip_string(text, i, q)
  if q == "'" and text:sub(i - 1, i - 1):find("%w") then return i end
  local k = i + 1
  while k <= #text do
    local c = text:sub(k, k)
    if c == "\\" then
      k = k + 1
    elseif c == q then
      return k
    elseif c == "\n" and q ~= "`" then
      return i
    end
    k = k + 1
  end
  return i
end

--- The nearest function call name(…) around [s, e): os at the name, the
--- open paren at [oe-1, oe), the close paren at [cs, ce). Strings are skipped.
---@param text string
---@param s integer
---@param e integer
---@return hxsurround.Match?
function M.call(text, s, e)
  local stack, best, i = {}, nil, 1
  while true do
    local at = text:find("[\"'`()]", i)
    if not at then break end
    i = at
    local c = text:sub(i, i)
    if c == "(" then
      stack[#stack + 1] = i
    elseif c == ")" then
      local p = table.remove(stack)
      if p then
        local k = p - 1
        while k >= 1 and text:sub(k, k):find("[%w_%.:]") do k = k - 1 end
        local name = text:sub(k + 1, p - 1):gsub("^[%.:]+", "")
        if name ~= "" and not name:find("^%d") and not keywords[name] then
          best = keep(best, { os = p - 1 - #name, oe = p, cs = i - 1, ce = i, name = name }, s, e)
        end
      end
    else
      i = skip_string(text, i, c)
    end
    i = i + 1
  end
  return best
end

--- The nearest open … close around [s, e), nested; equal ones pair up on
--- the line of s (as markdown markers do).
---@param text string
---@param s integer
---@param e integer
---@param open string
---@param close string
---@return hxsurround.Match?
function M.pair(text, s, e, open, close)
  if open == close then return M.marker(text, s, e, open) end
  local stack, best, i = {}, nil, 1
  while true do
    local a, b = text:find(open, i, true), text:find(close, i, true)
    if not a and not b then break end
    if a and (not b or a < b) then
      stack[#stack + 1] = a
      i = a + #open
    else
      local o = table.remove(stack)
      if o then best = keep(best, { os = o - 1, oe = o - 1 + #open, cs = b - 1, ce = b - 1 + #close }, s, e) end
      i = b + #close
    end
  end
  return best
end

--- A marker pair on the line of s around [s, e): the line's markers pair
--- up from its start, first with second, third with fourth.
---@param text string
---@param s integer
---@param e integer
---@param mark string
---@return hxsurround.Match?
function M.marker(text, s, e, mark)
  local ls = s
  while ls > 0 and text:sub(ls, ls) ~= "\n" do ls = ls - 1 end
  local le = text:find("\n", s + 1, true)
  le = le and le - 1 or #text
  local line, found, pos = text:sub(ls + 1, le), {}, 1
  while true do
    local a = line:find(mark, pos, true)
    if not a then break end
    found[#found + 1] = ls + a - 1
    pos = a + #mark
  end
  for k = 1, #found - 1, 2 do
    local m = { os = found[k], oe = found[k] + #mark, cs = found[k + 1], ce = found[k + 1] + #mark }
    if m.os <= s and math.min(e, le) <= m.ce then return m end
  end
end

--- The fenced code block (``` lines) around line `row` of `lines`: the rows
--- of its fences, 1-based.
---@param lines string[]
---@param row integer
---@return integer? first
---@return integer? last
function M.fence(lines, row)
  local open
  for i, l in ipairs(lines) do
    if l:find("^%s*```") then
      if not open then
        open = i
      elseif i >= row and open <= row then
        return open, i
      else
        open = nil
      end
    end
  end
end

return M
