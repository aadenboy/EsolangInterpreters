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

local file = io.open(arg[1], "r")
assert(file, "File not found")
local code = file:read("*a")
file:close()
code = code:gsub("[^%^%(%)%[%]]", "")
print(code)
function parse(s)
  local commands = {}
  local i = 1
  repeat
    local at = s:sub(i)
    if at:match("^%^*[%(%)]") then
      local nestings, command, next = at:match("^(%^*)([%(%)])()")
      table.insert(commands, {type = command, nestings = #nestings})
      i = i + next - 1
    elseif at:match("^%^*%b[]") then
      local nestings, inner, next = at:match("^(%^*)(%b[])()")
      local incmds = parse(inner:sub(2, -2))
      table.insert(commands, {type = "[]", nestings = #nestings, inner = incmds})
      i = i + next - 1
    else i = i + 1 end
  until i > #s
  return commands
end
local commands = parse(code)

local memory = {pointer = 0}

local dindexes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
function debug(m, pre, indent)
  indent = indent or ""
  local s = ""
  local min = 0
  local maxn = 1
  for i,v in pairs(m) do
    if type(i) == "number" then
      min = math.min(min, i)
      if #tostring(v.pointer) > maxn then maxn = #tostring(v.pointer) end
    end
  end
  s = s..indent..pre.." "..(" "):rep(4 + maxn):rep(m.pointer - min)..("v"):rep(3 + maxn).."\n"..indent..pre.." "
  local afters = ""
  for i=min, 0 do
    local index = dindexes:sub(1-i, 1-i)
    local value = m[i] and (m[i].unusable and "X" or m[i].pointer) or 0
    local pad = (" "):rep(maxn - #tostring(value))
    s = s..index.."["..pad..value.."] "
    if m[i] and not m[i].unusable then afters = afters..debug(m[i], pre..index, indent.."\t").."\n" end
  end
  s = s.."\n"..afters:sub(1, -2)
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
  previouscommand = ("^"):rep(command.nestings)..command.type
  print(debug(memory, ""))
  io.read()
  if command.type == "(" then
    local m = traverse(command.nestings)
    if m then m.pointer = m.pointer - 1 end
    traverse(command.nestings + 1)
  elseif command.type == ")" then
    local m = traverse(command.nestings)
    if m then
      repeat
        m.pointer = m.pointer + 1
        local newm = traverse(command.nestings + 1)
      until m.pointer > 0 or not newm or newm.pointer > m.pointer
      if m.pointer > 0 then m.unusable = true end
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
