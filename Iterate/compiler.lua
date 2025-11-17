assert(arg[1], "Usage: lua compile.lua <file>")
local prog = arg[1] or ""
local file = io.open(prog, "r")
assert(file, "File not found")
local code = file:read("*a")
file:close()

function dump(thing, depth)
    if type(thing) ~= "table" then return type(thing) == "string" and "\""..thing.."\"" or tostring(thing) end
    depth = depth or 1
    local build = "{"
    local prefix = ("  "):rep(depth)
    local any = false
    for i,v in pairs(thing) do
        any = true
        build = build.."\n"..prefix
              .."["..(type(i) == "string" and "\""..i.."\"" or tostring(i)).."]"
              .." = "..dump(v, depth + 1)..","
    end
    return any and build:sub(1, -2).."\n"..prefix:sub(1, -2).."}" or "{}"
end

local ii = 1
repeat
  if code:sub(ii, ii+4) == "((*))" then
    local name = code:sub(ii+5):match("^[^<>:\"/\\|%?%*\n]+")
    assert(name, "Expected filename")
    local ifile = io.open(name, "r")
    assert(ifile, "File "..name.." not found")
    local contents = ifile:read("*a")
    ifile:close()
    local prei = ii
    ii = ii + 5 + #name
    local include = ""
    local included = {}
    local noinclude = false
    while true do
      local macro, alias, after = code:sub(ii):match("^<%s*([%w_]+)%s*([%w_]*)%s*%>()")
      if code:sub(ii):match("^%<%s*!%s*%>") then
        noinclude = true
        ii = ii + 2
        break
      end
      if not macro then break end
      include = include.."(("..alias.."*))"..contents:match("^%(%("..macro.."%*%)%)([%w_ ]+%b<>)")
      included[macro] = true
      ii = ii + after
    end
    if not noinclude then
      for macro, rest in contents:gmatch("%(%(([%w_]+)%*%)%)([%w_ ]+%b<>)") do
        print(macro, rest)
        if not included[macro] then
          include = include.."(("..macro.."*))"..rest
        end
      end
    end
    code = code:sub(1, prei-1)..include..code:sub(ii+1)
  else
    ii = code:sub(ii):match("()%(%(%*%)%)") or #code+1
  end
until ii > #code

local macros = {}
local labels = {}
local knownlabels = {}
local count = 0
code = code
  :gsub("//[^\n]*", "") -- remove comments
  :gsub("%(%(([%w_]+)%*%)%)([%w_ ]+)(%b<>)", function(name, arglist, inner) -- store macros
    local args = {}
    for arg in arglist:gmatch("([%w_]+)") do
      table.insert(args, arg)
    end
    macros[name] = {name = name, args = args, code = inner:sub(2, -2)}
    return ""
  end)
  :gsub("([!&$=%(])([%w_]+)", function(c, l) -- store labels
    knownlabels[l] = true
    return c..l
  end)
  :gsub("n:([%w_]+)", function(l) -- store labels
    knownlabels[l] = true
    return "n:"..l
  end)

function expandmacro(macro, prefix, args, previous)
  if previous[macro] then error("Recursion is not allowed. Found in "..macro.name) end
  previous[macro] = true
  code = macro.code
    :gsub("%(([%w_]+)%(([%w_]+)%*", "(:%1(:%2*") -- preserve macros
    :gsub("([!&$=%(])([%w_]+)", function(c, l) -- prefix labels
      if knownlabels[l] then return c..l
      else return c..prefix..l end
    end)
    :gsub("n:([%w_]+)", function(l) -- prefix labels
      if knownlabels[l] then return "n:"..l
      else return "n:"..prefix..l end
    end)
    :gsub("%(:([%w_]+)%(:([%w_]+)%*", "(%1(%2*") -- restore macros
    :gsub("?([%w_]+)", function(arg) -- replace args
      if not args[arg] then error("Argument "..arg.." not found in macro "..macro.name) end
      return args[arg]
    end)
  code = expand(code, prefix, args, previous)
  previous[macro] = nil
  return code
end

function expand(c, topprefix, args, previous)
  local i = 1
  repeat
    local prefix, macro, after = c:sub(i):match("^%(([%w_]+)%(([%w_]+)%*%)%)()")
    if prefix and macro then
      local macrostr = macro
      local macro = macros[macro]
      if not macro then error("Macro "..macrostr.." not found") end
      local prei = i
      i = i + after - 1
      local largs = {}
      for i,v in ipairs(args) do
        largs[i] = v
      end
      local argi = 1
      while true do
        local arg = c:sub(i):match("^%b<>")
        if not arg then break end
        largs[macro.args[argi]] = arg:sub(2, -2):gsub("^%s*(.-)%s*$", "%1")
        argi = argi + 1
        i = i + #arg
      end
      local out = expandmacro(macro, topprefix..prefix, largs, previous)
      c = c:sub(1, prei-1)..out..c:sub(i+1)
      i = prei + #out
    else
      local prei = i
      i = c:sub(i):match("^.-()%([%w_]+%(")
      if not i then break end
      i = prei + i - 1
    end
  until i > #c
  return c
end

code = expand(code, "", {}, {})
---[[
code = code
  :gsub("([!&$=%(])([%w_]+)", function(c, l) -- replace labels
    count = count + (labels[l] and 0 or 1)
    labels[l] = labels[l] or count
    return c..labels[l]
  end)
  :gsub("n:([%w_]+)", function(l) -- replace labels
    count = count + (labels[l] and 0 or 1)
    labels[l] = labels[l] or count
    return "n"..labels[l]
  end)
  :gsub("%s+", "") -- remove whitespace
--]]
local outfile = io.open("out.it", "w")
outfile:write(code)
outfile:close()
