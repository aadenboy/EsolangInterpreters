assert(arg[1], "No program specified")
local program = arg[1]
local file = io.open(program, "r")
assert(file, "Could not open file "..program)
local code = file:read("*a")
file:close()
local out = arg[2]

function toutf8(cp) -- for lua 5.1+ https://stackoverflow.com/a/26237757
  if cp < 128 then
    return string.char(cp)
  end
  local suffix = cp % 64
  local c4 = 128 + suffix
  cp = (cp - suffix) / 64
  if cp < 32 then
    return string.char(192 + cp, c4)
  end
  suffix = cp % 64
  local c3 = 128 + suffix
  cp = (cp - suffix) / 64
  if cp < 16 then
    return string.char(224 + cp, c3, c4)
  end
  suffix = cp % 64
  cp = (cp - suffix) / 64
  return string.char(240 + cp, 128 + suffix, c3, c4)
end

local function dump(thing, depth, seen)
  if type(thing) ~= "table" then return type(thing) == "string" and "\""..thing.."\"" or tostring(thing) end
  seen = seen or {}
  if seen[thing] then return "{...}" end
  seen[thing] = true
  depth = depth or 1
  local build = "{"
  local prefix = ("  "):rep(depth)
  local any = false
  for i,v in pairs(thing) do
      any = true
      build = build.."\n"..prefix
            .."["..(type(i) == "string" and "\""..i.."\"" or tostring(i)).."]"
            .." = "..dump(v, depth + 1, seen)..","
  end
  return any and build:sub(1, -2).."\n"..prefix:sub(1, -2).."}" or "{}"
end

code = code:gsub("%f[/]/%*.-%*/", "")
         :gsub("//[^\n]+", "")
         :gsub("∞", "i")
         :gsub("[^()<>*0-9~ni=?%^!@&%%%$\n]", "") -- \n to preserve line numbers

local loops = {}
local current = {}
local labels = {}
local highestlabel = 0
local i = 1
function rcassert(from, tag)
  if tag == "" then return true end
  if from.labels[tag] then return false, from.labels[tag] end
  if from == loops[1] then return true end
  return rcassert(from.parent, tag)
end
function rcsearch(from, tag)
  if tag == "" then return end
  if from.label == tag then return from end
  if from == loops[1] then return from end
  return rcsearch(from.parent, tag)
end
local line = 1
local parseline = 1
repeat
    local s = code:sub(i)
    if s:match("^\n") then line = line + 1 end
    
    if s:match("^%(%*%).-<") and #loops == 0 then
      assert(s:match("^%(%*%)[^<]*%b<>"), "Unclosed loop at line "..line)
      loops[1] = {
          label = "^",
          amount = s:match("^%(%*%)(.-)%b<>"),
          commands = {},
          parent = {},
          n = 0, visits = 0,
          labels = {},
          line = line,
          parseline = parseline
      }
      current = loops[1]
      labels["^"] = 0
      highestlabel = 1
      i = i + s:match("^%(%*%).-()%b<>")
      parseline = parseline + 1
    elseif s:match("^%(%d+%*%).-<") then
      assert(s:match("^%(%d+%*%)[^<]*%b<>"), "Unclosed loop at line "..line)
      local loop = {
          label = s:match("^%((%d+)"),
          amount = s:match("^%(%d+%*%)(.-)%b<>"),
          commands = {},
          parent = current,
          n = 0, visits = 0,
          labels = {},
          line = line,
          parseline = parseline
      }
      local valid, previous
      local succ, err = pcall(function() valid, previous = rcassert(loop.parent, loop.label) end)
      if not succ then print(dump(loop.parent)) print(dump(loop)) error(err) end
      assert(valid, "Duplicate labels in the same scope are not allowed (label "..loop.label.." at line "..line..", previously defined at line "..(previous and previous.line or "")..")")
      for i,v in ipairs(loop.parent.labels or {}) do
          loop.labels[i] = v
      end
      labels[loop.label] = 0
      highestlabel = math.max(highestlabel, tonumber(loop.label))
      loop.labels[loop.label] = loop
      loop.parent.labels[loop.label] = loop
      table.insert(loops, loop)
      table.insert(current.commands, loop)
      current = loop
      i = i + s:match("^%(%d+%*%).-()%b<>")
      parseline = parseline + 1
    elseif s:match("^%*.-<") then
      assert(s:match("^%*[^<]*%b<>"), "Unclosed loop at line "..line)
      local loop = {
          label = "",
          amount = s:match("^%*(.-)%b<>"),
          commands = {},
          parent = current,
          n = 0, visits = 0,
          labels = {},
          line = line,
          parseline = parseline
      }
      table.insert(loops, loop)
      table.insert(current.commands, loop)
      current = loop
      i = i + s:match("^%*.-()%b<>")
      parseline = parseline + 1
    elseif s:match("^[!&]") then
      local kind = s:match('^(.)')
      local command = {
          type = kind,
          param = s:match("^"..kind.."(%d+)") or s:match("^"..kind.."(%^)"),
          line = line,
          parseline = parseline
      }
      table.insert(current.commands, command)
      i = i + 1 + #(command.param or "")
      parseline = parseline + 1
    elseif s:match("^[~%%]?@") then
      local kind = s:match("^[~%%]?@")
      local command = {
          type = kind,
          line = line,
          parseline = parseline
      }
      table.insert(current.commands, command)
      i = i + #kind
      parseline = parseline + 1
    elseif s:match("^%$[0-9%^]?") then
      local command = {
          type = "$",
          param = s:match("^%$(%d+)") or s:match("^%$(%^)"),
          line = line,
          parseline = parseline
      }
      table.insert(current.commands, command)
      i = i + 1 + #command.param
      parseline = parseline + 1
    elseif s:match("^>") then
      if #current.commands > 0 then parseline = parseline + 1 end
      current = current.parent
      i = i + 1
    else
      i = i + 1
    end
until i >= #code

current = loops[1]
if not current or current.label ~= "^" then return end

local boiler = io.open("boiler.c", "r")
assert(boiler, "Could not open boilerplate file boiler.c")
local boilerplate = boiler:read("*a")
boiler:close()
local cfile = "void iterateprogram() {\n"

local li = 0
local vars = {}
local jumps = {} -- disambiguation
-- I<index> for indices, R<index> for remaining loops, V<index> for visits
-- B<index> for break flags, C<index> for continue flags (if past loop boundaries)
-- u<index> for unique loop identifiers
function traverse(loop, indent)
    vars[loop] = "u"..li
    local i = "u"..li
    if loop.label == "^" then loop.label = "top" end
    jumps[loop.label] = (jumps[loop.label] or 0) + 1
    li = li + 1
    indent = indent or "  "
    local amount = ""
        if loop.amount == ""            then amount = "0"
    elseif tonumber(loop.amount)        then amount = "(uint64_t) "..loop.amount
    elseif loop.amount == "i"           then amount = "18446744073709551615ULL"
    elseif loop.amount == "?"           then amount = "readnum()"
    elseif loop.amount == "~?"          then amount = "readutf8()"
    elseif loop.amount == "%?"          then amount = "(uint64_t)pop()"
    elseif loop.amount == "n"           then amount = loop.parent.label and "I"..vars[loop.parent] or "0"
    elseif loop.amount:match("^n%d+$")  then amount = "I"..loop.amount:match("^n(%d+)")
    elseif loop.amount == "n^"          then amount = "Itop"
    elseif loop.amount == "~n"          then amount = loop.parent.label and "R"..vars[loop.parent] or "0"
    elseif loop.amount:match("^~n%d+$") then amount = "R"..loop.amount:match("^~n(%d+)")
    elseif loop.amount == "~n^"         then amount = "Rtop"
    elseif loop.amount == "="           then amount = loop.parent.label and "V"..vars[loop.parent] or "0"
    elseif loop.amount:match("^=%d+$")  then amount = "V"..loop.amount:match("^=(%d+)")
    elseif loop.amount == "=^"          then amount = "Vtop" end
    if loop.label ~= "" then cfile = cfile..indent.."V"..loop.label.."++;\n" end
    cfile = cfile..indent.."V"..i.."++;\n"
    if amount == "0" or #loop.commands == 0 then return end
    cfile = cfile..indent.."uint64_t A"..i.." = "..amount..";\n"
                 ..indent.."for (uint64_t I"..i.." = 1; ".."I"..i.." <= A"..i.."; I"..vars[loop].."++) {\n"
    indent = indent.."  "
    cfile = cfile..indent.."uint64_t R"..i.." = A"..i.." - I"..i..";\n"
    if loop.label ~= "" then
        cfile = cfile..indent.."uint64_t I"..loop.label.." = I"..i..";\n"
                     ..indent.."uint64_t R"..loop.label.." = R"..i..";\n"
    end
    for _,v in ipairs(loop.commands) do
        if v.type then
                if v.type == "!" and not v.param    then cfile = cfile..indent.."break;\n"
            elseif v.type == "!" and v.param ~= "^" then cfile = cfile..indent.."goto B"..v.param.."_"..jumps[v.param]..";\n"
            elseif v.type == "!" and v.param == "^" then cfile = cfile..indent.."goto Btop_1;\n"
            elseif v.type == "&" and not v.param    then cfile = cfile..indent.."continue;\n"
            elseif v.type == "&" and v.param ~= "^" then cfile = cfile..indent.."goto C"..v.param.."_"..jumps[v.param]..";\n"
            elseif v.type == "&" and v.param == "^" then cfile = cfile..indent.."goto Ctop_1;\n"
            elseif v.type == "@"                    then cfile = cfile..indent.."printf(\"%\"PRIu64, I"..i..");\n"
            elseif v.type == "~@"                   then cfile = cfile..indent.."oututf8(I"..i..");\n"
            elseif v.type == "%@"                   then cfile = cfile..indent.."putchar(I"..i.." & 0xFF);\n"
            elseif v.type == "$" and not v.param    then cfile = cfile..indent.."V"..i.." = 0 ;\n"
            elseif v.type == "$" and v.param ~= "^" then cfile = cfile..indent.."V"..v.param.." = 0 ;\n"
            elseif v.type == "$" and v.param == "^" then cfile = cfile..indent.."Vtop = 0 ;\n" end
        else
            traverse(v, indent)
        end
    end
    if loop.label ~= "" then cfile = cfile..indent.."C"..loop.label.."_"..jumps[loop.label]..":\n" end
    indent = indent:sub(1, -3)
    cfile = cfile..indent.."}\n"
    if loop.label ~= "" then cfile = cfile..indent.."B"..loop.label.."_"..jumps[loop.label]..":\n" end
end
traverse(current)
for i,v in pairs(labels) do
    cfile = "uint64_t V"..(i == "^" and "top" or i).." = 0;\n"..cfile
end
for i=0, li do
    cfile = "uint64_t Vu"..i.." = 0;\n"..cfile
end
cfile = cfile.."}\n"
cfile = cfile:gsub("(%s*)([BC][%d%l]+_%d+):", function(s, l)
    if cfile:match("goto "..l) then
        return s..l..":"
    else return "" end
end)
cfile = cfile:gsub("(%s*)uint64_t (%S+) = (.-);", function(s, l, v)
    if l:match("[AI]u%d+") or cfile:match("Au%d+ = "..l) or cfile:match(l.." = 0 ;") then
        return s.."uint64_t "..l.." = "..v..";"
    else return "" end
end)
cfile = cfile:gsub("(%s*)(V[%d%l]+)%+%+;", function(s, l)
    if cfile:match(l.." = 0;") then
        return s..l.."++;"
    else return "" end
end):gsub("= 0 ;", "= 0;")
print(cfile)
if not arg[2] then return end
local outfile = io.open(arg[2], "w")
outfile:write((boilerplate:gsub("//%$PROGRAM%$//", function() return cfile end)))
outfile:close()
