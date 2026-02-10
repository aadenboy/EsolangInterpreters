local gargs = {}
local flags = {
    dump = false,          -- dump the parsed program expanded to the console
    parserdump = false,    -- dump the parsed program as a lua table to the console
    verbose = false,       -- prevent simplifying algebraic constructs (see Iterate/Loop algebra)
    debugsimplify = false, -- debug the simplification process
}
for i=1, #arg do
    local a = arg[i]
    if a:match("^%-%-[^=]+=%-?%d*%.?%d+") then
        local name, value = a:match("^%-%-(.-)=(%-?%d*%.?%d+)")
        if type(flags[name]) == "number" then flags[name] = tonumber(value) or flags[name] end
    elseif a:match("^%-%-[^=]+=") then
        local name, value = a:match("^%-%-(.-)=(.+)")
        if type(flags[name]) == "string" then flags[name] = value end
    elseif a:sub(1, 2) == "--" and #a > 2 and type(flags[a:sub(3)]) == "boolean" then
        flags[a:sub(3)] = true
    else
        table.insert(gargs, a)
    end
end

assert(arg[1], "No program specified")
local program = gargs[1]
local file = io.open(program, "r")
assert(file, "Could not open file "..program)
local code = file:read("*a")
file:close()
local out = gargs[2] or program:gsub("%.it", ".c")

local load = loadstring or load
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

local prints = {}
code = code:gsub("%f[/]/%*.-%*/", "")
         :gsub("//[^\n]+", "")
         :gsub("∞", "i")
         :gsub("%b{}", function(s)
             table.insert(prints, s:sub(2, -2))
             return "|"..#prints
         end)
         :gsub("[^()<>*0-9~ni=?%^!@&%%%$|\n]", "") -- \n to preserve line numbers

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
    elseif s:match("^|") then
        local command = {
            type = "|",
            param = prints[tonumber(s:match("^|(%d+)"))],
            line = line,
            parseline = parseline
        }
        table.insert(current.commands, command)
        i = i + s:match("^|%d+()") - 1
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

function issimple(n, eq)
    return
        n == "" or
        tonumber(n) or
        (n:match("%?") and #eq == 0) or
        n:match("n") or
        n:match("=.+")
end
function choose(n, i, k)
    if not tonumber(n) then
        local out = n
        local f, x = 1, 1
        for j=-k+1+i, i do
            out = out..(j == 0 and "" or "*("..n..(j < 0 and "-"..-j or "+"..j)..")")
            f = f * x
            x = x + 1
        end
        return out.."/"..f
    else
        local cur = 1
        local f, x = 1, 1
        for j=-k+1+i, i do
            cur = cur * (n + j)
            f = f * x
            x = x + 1
        end
        return cur/f
    end
end
function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for i,v in pairs(t) do
        out[i] = copy(v)
    end
    return out
end
function simplify(loop)
    local increments = {}
    local encountered = {seen = {}, used = {}}
    local simple = true
    local function check(loop, eq)
        if loop.label ~= "" then
            encountered.seen[loop.label] = true
            table.insert(increments, {label = loop.label, amount = eq})
        end
        if loop.amount:match("=.+") or loop.amount:match("n.+") then
            encountered.used[loop.amount:match("[=n](.+)")] = true
        end
        if issimple(loop.amount, eq) then
            local hit = {}
            local broken = false
            for _,v in ipairs(loop.commands) do
                if v.type and v.type ~= "!" then simple = v.type.." is complex" return end
                if v.type == "!" and v.param then simple = "! with param is complex" return end
                if v.type == "!" then broken = true break end
                table.insert(hit, v)
            end
            local neq = copy(eq)
            if loop.amount:match("n$") and not broken and #neq > 0 then
                local cur = neq[#neq]
                if cur.broken then
                    neq[#neq] = {type = "const", amount = loop.amount == "~n" and "("..cur.broken.."-!!"..cur.broken..")" or 1, broken = not loop.amount == "~n"}
                else
                    neq[#neq] = {type = "binom", amount = cur.amount, i = (cur.i or 0) + (loop.amount:match("~") and 0 or 1), k = (cur.k or 1) + 1}
                end
            else table.insert(neq, {type = "const", amount = broken and 1 or loop.amount, broken = broken and loop.amount}) end
            for _,v in ipairs(hit) do
                check(v, neq)
            end
        else
            simple = loop.amount.." is complex"
        end
    end
    check(loop, {})
    for i in pairs(encountered.seen) do
        if encountered.used[i] then simple = i.." is both seen and used" break end
    end
    if simple == true then
        loop.simplified = {} 
        for _,v in ipairs(increments) do
            local final = ""
            local pre
            for _,b in ipairs(v.amount) do
                if not b.broken and b.type == "const" then
                    if b.amount:match("%?.+%?") then
                        pre = b.amount:match("[~%%]?%?")
                        b.amount = b.amount:gsub("[~%%]?%?", "$1")
                    end
                    final = final..b.amount.."*"
                elseif not b.broken then
                    if b.amount:match("%?") then
                        pre = b.amount
                        b.amount = "$1"
                    end
                    final = final..choose(b.amount, b.i, b.k).."*"
                elseif b.broken and b.broken:match("[n=].+") then
                    final = final.."!!"..b.broken.."*"
                end
            end
            if final == "" then final = "1*" end
            table.insert(loop.simplified, {label = v.label, amount = final:sub(1, -2), pre = pre})
            if flags.debugsimplify then print(v.label, final:sub(1, -2), pre) end
        end
    else
        if flags.debugsimplify then print(simple) end
        for _,v in ipairs(loop.commands) do
            if not v.type then simplify(v) end
        end
    end
end
if not flags.verbose then simplify(current) end

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
function tovalue(loop, amount)
    amount = amount or loop.amount
        if not amount              then return "0"
    elseif amount == ""            then return "0"
    elseif tonumber(amount)        then return "(uint64_t) "..amount
    elseif amount == "i"           then return "18446744073709551615ULL"
    elseif amount == "?"           then return "readnum()"
    elseif amount == "~?"          then return "readutf8()"
    elseif amount == "%?"          then return "(uint64_t)pop()"
    elseif amount == "n"           then return loop.parent.label and "I"..vars[loop.parent] or "0"
    elseif amount:match("^n%d+$")  then return "I"..amount:match("^n(%d+)")
    elseif amount == "n^"          then return "Itop"
    elseif amount == "~n"          then return loop.parent.label and "R"..vars[loop.parent] or "0"
    elseif amount:match("^~n%d+$") then return "R"..amount:match("^~n(%d+)")
    elseif amount == "~n^"         then return "Rtop"
    elseif amount == "="           then return loop.parent.label and "V"..vars[loop.parent] or "0"
    elseif amount:match("^=%d+$")  then return "V"..amount:match("^=(%d+)")
    elseif amount == "=^"          then return "Vtop" end
end
local pi = 0
function simpletraverse(loop, indent)
    for _,v in ipairs(loop.simplified) do
        if v.pre then
            cfile = cfile..indent.."uint64_t P"..pi.." = "..tovalue(loop, v.pre)..";\n"
            v.amount = v.amount:gsub("%$1", "P"..pi)
            pi = pi + 1
        end
        local namount = v.amount:gsub("[^%+%-%*/%(%)!]+", function(a) return tovalue(loop, a) end)
        cfile = cfile..indent.."V"..v.label.." += "..namount..";\n"
    end
end
function traverse(loop, indent)
    vars[loop] = "u"..li
    local i = "u"..li
    if loop.label == "^" then loop.label = "top" end
    jumps[loop.label] = (jumps[loop.label] or 0) + 1
    li = li + 1
    indent = indent or "  "
    local amount = tovalue(loop)
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
            elseif v.type == "$" and v.param == "^" then cfile = cfile..indent.."Vtop = 0 ;\n"
            elseif v.type == "|"                    then
                local args = {}
                local inner = v.param
                    :gsub("%$(.-)%$", function(s)
                        if not tovalue(loop, s) then return "$"..s.."$"
                        else
                            table.insert(args, tovalue(loop, s))
                            return "%\"PRIu64\""
                        end
                    end)
                cfile = cfile..indent.."printf(\""..inner.."\""..(#args > 0 and ", "..table.concat(args, ", ") or "")..");\n"
            end
        elseif v.simplified then
            simpletraverse(v, indent)
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

-- getting rid of unused stuff
cfile = cfile:gsub("(%s*)([BC][%d%l]+_%d+):", function(s, l) -- labels
    if cfile:match("goto "..l) then
        return s..l..":"
    else return "" end
end)
cfile = cfile:gsub("(%s*)uint64_t (%S+) = (.-);", function(s, l, v) -- variables
    if l:match("[AI]u%d+") or cfile:match("Au%d+ = "..l) or cfile:match(l.." = 0 ;") or cfile:match("%+=[^;]*"..l.."[^;]*;") then
        return s.."uint64_t "..l.." = "..v..";"
    else return "" end
end)
cfile = cfile:gsub("(%s*)(V[%d%l]+)(%s*%+[%+=])(.-);", function(s, l, o, n) -- visits
    if cfile:match(l.." = 0;") then
        return s..l..o..n..";"
    else return "" end
end):gsub("= 0 ;", "= 0;")
cfile = cfile:gsub(" %+= %(uint64_t%) 1;", "++;") -- jankery
if not arg[2] then print(cfile) return end
local outfile = io.open(arg[2], "w")
assert(outfile, "Could not open output file "..arg[2])
outfile:write((boilerplate:gsub("//%$PROGRAM%$//", function() return cfile end)))
outfile:close()
