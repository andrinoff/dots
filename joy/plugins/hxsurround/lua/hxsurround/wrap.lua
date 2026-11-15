-- hxsurround.wrap: what a key wraps with, and the text a wrap makes.
local M = {}

-- Brackets and quotes, as m s has them; a closing bracket wraps as its pair.
M.pairs = {
  ["("] = { "(", ")" }, [")"] = { "(", ")" }, ["["] = { "[", "]" }, ["]"] = { "[", "]" },
  ["{"] = { "{", "}" }, ["}"] = { "{", "}" }, ["<"] = { "<", ">" }, [">"] = { "<", ">" },
  ['"'] = { '"', '"' }, ["'"] = { "'", "'" },
}

-- Markdown markers by key.
M.markdown = { ["*"] = { "**", "**" }, ["_"] = { "_", "_" }, ["`"] = { "`", "`" }, ["~"] = { "~~", "~~" } }

local mirror = { ["("] = ")", [")"] = "(", ["["] = "]", ["]"] = "[", ["{"] = "}", ["}"] = "{", ["<"] = ">", [">"] = "<" }

--- The close of a custom open: punctuation reversed with brackets mirrored
--- ("{{ " → " }}", "<!-- " → " -->", "<?php " → " ?>", "/* " → " */"); an
--- open of words without brackets closes with itself.
---@param open string
---@return string
function M.close_of(open)
  local bracket = open:find("[%(%[{<]") ~= nil
  if not bracket and open:find("%w") then return open end
  local core = open:gsub("%w", "")
  local close = core:reverse():gsub("[%(%)%[%]{}<>]", mirror)
  return (close:gsub("!>", ">")) -- <!-- and <![CDATA[ close without the !
end

--- A tag typed at the prompt ("div class=x", "<p>") as open, close and name.
---@param input string
---@return string? open
---@return string? close
---@return string? name
function M.tag(input)
  input = input:gsub("^%s*<?", ""):gsub(">?%s*$", "")
  local name = input:match("^[^%s/>]+")
  if not name then return nil end
  return "<" .. input .. ">", "</" .. name .. ">", name
end

--- One indent level of the current buffer.
---@return string
function M.unit()
  local b = joy.buffer.get(0)
  return b and b.indent or "\t"
end

--- Whole lines wrapped as a block: open and close on lines of their own at
--- the first line's indent, the lines between indented by `unit`.
---@param lines string[]
---@param open string
---@param close string
---@param unit string
---@return string[]
function M.block(lines, open, close, unit)
  local ind = (lines[1] or ""):match("^%s*")
  local out = { ind .. open }
  for _, l in ipairs(lines) do out[#out + 1] = l == "" and "" or unit .. l end
  out[#out + 1] = ind .. close
  return out
end

--- Lines of a block taken out of it: one indent level less each.
---@param lines string[]
---@param unit string
---@return string[]
function M.dedent(lines, unit)
  local out = {}
  for i, l in ipairs(lines) do
    if l:sub(1, #unit) == unit then
      l = l:sub(#unit + 1)
    elseif l:sub(1, 1) == "\t" then
      l = l:sub(2)
    else
      l = l:gsub("^" .. string.rep(" ?", #unit), "")
    end
    out[i] = l
  end
  return out
end

return M
