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

local gargs = {}
local flags = {
    dump = false,         -- dump the parsed program expanded to the console and exit
    parserdump = false,   -- dump the parsed program as a lua table to the console and exit
    maxdepth = math.huge, -- maximum depth to show
    direct = false,       -- only show the currently selected branch
    show = ".+",          -- regex of which branches to show (overrides maxdepth and direct)
    showloose = ".+",     -- same as show but doesn't preserve entire branch
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
if flags.show == ".+" then flags.show = nil end
if flags.show then
  flags.maxdepth = math.huge
  flags.direct = false
end

local file = io.open(gargs[1], "r")
assert(file, "File not found")
local code = file:read("*a")
file:close()
code = code:gsub("[^%^%(%)%[%]\n]", "")
print(code)
local line = 1
function parse(s)
  local commands = {}
  local i = 1
  repeat
    local at = s:sub(i)
    if at:match("^%^*[%(%)]") then
      local nestings, command, next = at:match("^(%^*)([%(%)])()")
      table.insert(commands, {type = command, nestings = #nestings, line = line})
      i = i + next - 1
    elseif at:match("^%^*%b[]") then
      local nestings, inner, next = at:match("^(%^*)(%b[])()")
      local preline = line
      local incmds = parse(inner:sub(2, -2))
      table.insert(commands, {type = "[]", nestings = #nestings, inner = incmds, line = preline})
      i = i + next - 1
    elseif at:sub(1, 1) == "\n" then
      line = line + 1
      i = i + 1
    else i = i + 1 end
  until i > #s
  return commands
end
local commands = parse(code)
if flags.dump then
  print(code)
  os.exit()
elseif flags.parserdump then
  print(dump(commands))
  os.exit()
end

local memory = {pointer = 0}

local dindexes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
function debug(m, pre, indent)
  indent = indent or ""
  local s = ""
  local max = 0
  local maxn = 1
  for i,v in pairs(m) do
    if type(i) == "number" then
      max = math.max(max, i)
      if #tostring(v.pointer) > maxn then maxn = #tostring(v.pointer) end
    end
  end
  s = s..indent..pre.." "..(" "):rep(4 + maxn):rep(m.pointer)..("v"):rep(3 + maxn).."\n"..indent..pre.." "
  local afters = ""
  for i=0, max do
    local index = dindexes:sub(i+1, i+1)
    local value = m[i] and (m[i].unusable and "X" or m[i].pointer) or 0
    local pad = (" "):rep(maxn - #tostring(value))
    s = s..index.."["..pad..value.."] "
    local matches = not flags.show
    if flags.show then for match in flags.show:gmatch("[^,]+") do
        if (pre..index):match("^"..match.."$") then matches = true; break end
    end end
    if m[i] and not m[i].unusable and matches
    and (not flags.direct or i == m.pointer)
    and (not flags.maxdepth or #pre < flags.maxdepth) then
      afters = afters.."\n"..debug(m[i], pre..index, indent.."\t")
    end
  end
  s = s..afters
  return s
end

function traverse(n)
  if memory.unusable then return nil end
  if n == 0 then return memory end
  local m = memory
  for i=1, n do
    if m[m.pointer] and m[m.pointer].unusable then return nil end
    m[m.pointer] = m[m.pointer] or {pointer = 0}
    m = m[m.pointer]
  end
  return m
end
local previouscommand = ""
function run(command)
  print("\x1B[2J\x1B[H"..previouscommand)
  previouscommand = ("^"):rep(command.nestings)..command.type.." at line "..command.line
  local debugged = debug(memory, "")
  debugged = debugged:gsub("([ \t]+([a-zA-Z]+) [^\n]+\n?)", function(a, index)
    for match in flags.showloose:gmatch("[^,]+") do
      if index:match("^"..match.."$") then return a end
    end
    return ""
  end)
  print(debugged)
  io.read()
  if command.type == ")" then
    local m = traverse(command.nestings)
    if m then m.pointer = m.pointer + 1 end
    traverse(command.nestings + 1)
  elseif command.type == "(" then
    local m = traverse(command.nestings)
    if m then
      repeat
        m.pointer = m.pointer - 1
        local newm = traverse(command.nestings + 1)
      until m.pointer < 0 or not newm or newm.pointer <= m.pointer
      if m.pointer < 0 then m.unusable = true end
    end
  elseif command.type == "[]" then
    local m = traverse(command.nestings + 1)
    while m do
      for i=1, #command.inner do
        run(command.inner[i])
      end
      m = traverse(command.nestings + 1)
    end
  end
end
for i,v in ipairs(commands) do
  run(v)
end
