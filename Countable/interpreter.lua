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

local gargs = {}
local flags = {
  dump = false,        -- dump the parsed program expanded to the console
  parserdump = false,  -- dump the parsed program as a lua table to the console
  emptyinput = false,  -- mark the input as empty to prevent CLI io
  debug = false,       -- run the program in debug mode (requires an input file or --emptyinput flag set)
  autocycle = false,   -- automatically cycle through the program in debug mode
  autocycledelay = -1, -- delay between cycles in debug mode in seconds (sets --autocycle to true)
  linesup = 5,         -- number of lines to show above the current line in debug mode
  linesdown = 5,       -- number of lines to show below the current line in debug mode
  stickyloops = false, -- show the lines of the parent loops in debug mode, even if they are out of view
  hideunlabeled = false, -- hide the indexes of unlabeled loops in debug mode
  maxindexes = math.huge,     -- maximum number of indexes to show in debug mode
  inputbytes = 10,      -- number of bytes to read from the input at a time in debug mode
  inputbytetype = "number", -- type of input bytes to show in debug mode (number, bits, hex, utf8)
  maxoutbytes = math.huge,     -- maximum number of bytes to show in the output in debug mode
  hidegarbage = false, -- hide any accumulators not referenced by the program or other accumulators in debug mode
}
for i=1, #arg do
  local a = arg[i]
  if a:match("^%-%-[^=]+=%-?[%di]*%.?[%di]+") then
    local name, value = a:match("^%-%-(.-)=(%-?[%di]*%.?[%di]+)")
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

local prog, inpath = gargs[1] or "", gargs[2]
local file = io.open(prog, "r")
assert(file, "File not found")
local code = file:read("*a")
file:close()
local input, inputbit = "", 1
if inpath then
  local infile = io.open(inpath, "r")
  assert(infile, "Input file not found")
  input = infile:read("*a")
  infile:close()
end
local usefile = inpath or flags.emptyinput
if flags.debug and not usefile and not flags.emptyinput then error("Debug mode requires an input file, or use the --emptyinput flag") end
if flags.autocycledelay >= 0 then flags.autocycle = flags.autocycledelay end

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
           :gsub("[^ia[%di]%+%*<>&@#~%%\n]", "") -- \n to preserve line numbers

local commands = {type = "loop", x = "", n = "1", parent = nil, parseline = 0}
local current = commands
local i = 1
local line = 1
local parseline = 1
repeat
  local s = code:sub(i)
  if s:match("^\n") then line = line + 1 end

  if s:match("^a*[%di]*%*a*[%di]+<") or s:match("^a*[%di]*%*i<") then
    assert(s:match("^a*[%di]*%*a*[%di]+%b<>") or s:match("a*[%di]*%*i%b<>"), "Unclosed loop at line "..line)
    local loop = {
      type = "loop",
      x = s:match("^(a*[%di]*)"),
      n = s:match("%*(a*[%di]+)") or "i",
      parent = current,
      parseline = parseline
    }
    table.insert(current, loop)
    current = loop
    i = i + #loop.x + #loop.n + 2
    parseline = parseline + 1
  elseif s:match("^a*[%di]+%+a*[%di]*") then
    local target, amount = s:match("^(a*[%di]+)%+(a*[%di]*)")
    amount = amount == "" and "1" or amount
    table.insert(current, {type = "+", x = target, n = amount, parseline = parseline})
    i = i + s:match("^a*[%di]+%+a*[%di]*()")
    parseline = parseline + 1
  elseif s:match("^a*[%di]+[&@]") then
    table.insert(current, {type = s:match("[&@]"), x = s:match("^a*[%di]+"), parseline = parseline})
    i = i + s:match("^a*[%di]+[&@]()")
    parseline = parseline + 1
  elseif s:match("^[%%#]a*[%di]+") then
    table.insert(current, {type = s:match("[%%#]"), n = s:match("^[%%#](a*[%di]+)"), parseline = parseline})
    i = i + s:match("^[%%#]a*[%di]+()")
    parseline = parseline + 1
  elseif s:match("^~") then
    table.insert(current, {type = "~", parseline = parseline})
    i = i + 1
    parseline = parseline + 1
  elseif s:match("^>") then
    if #current > 0 then parseline = parseline + 1 end
    current = current.parent or current
    i = i + 1
  else
    i = i + 1
  end
until i >= #code
local accumulators = {}

function ioprompt()
  if not usefile and inputbit > #input then input = io.read().."\0"; inputbit = 1 end
end
function parseamount(amount)
  if amount == "i" then return math.huge
  elseif amount:sub(1, 1) == "a" then
    local pointers, value = #amount:match("a+"), amount:match("[%di]+")
    value = tonumber(value) or math.huge
    repeat
      value = accumulators[value] or 0
      pointers = pointers - 1
    until pointers == 0
    return value
  else return tonumber(amount) or 0 end
end

local out = ""
local function indent(num, max)
  return (" "):rep(#tostring(max) - #tostring(num))..num
end
function progdump(loop, depth, from, to, sel, actloop, derefpointers, pointers)
  derefpointers = derefpointers or {}
  pointers = pointers or {}
  depth = depth or 0
  local build = ""
  if loop ~= commands then build = ("  "):rep(depth - 1)..loop.x.."*"..loop.n:gsub("i", "∞").."<"..(#loop > 0 and "\n" or "") end
  for _,v in ipairs(loop) do
    if v.x and v.x:match("a") and v.type ~= "loop" then derefpointers[v.x] = "x" end
    if v.n and v.n:match("aa") then derefpointers[v.n:sub(2)] = "v" end
    if v.x and v.x:match("^[%di]+$") and v.type ~= "loop" then pointers[tonumber(v.x)] = true end
    if v.n and v.n:match("^a[%di]+$") then pointers[tonumber(v.n:sub(2))] = true end
    if v.type ~= "loop" then
      build = build..("  "):rep(depth)..(v.x or "")..(v.type or "")..(v.n or "").."\n"
    else
      build = build..progdump(v, depth + 1, nil, nil, nil, nil, derefpointers).."\n"
    end
  end
  if loop ~= commands then build = build..("  "):rep(#loop > 0 and (depth - 1) or 0)..">" end
  if not from or not to then return build end

  local ancestors = {actloop}
  local sticky = {}
  local indmax = ""
  while true do
    local cur = ancestors[1]
    sticky[cur.parseline] = true
    if #cur.x > #indmax then indmax = cur.x end
    if cur.parent then table.insert(ancestors, 1, cur.parent) else break end
  end
  local finalout = ""
  local _, lines = build:gsub("\n", "\n")
  lines = lines + 1
  if from < 1 then to = to - from + 1; from = 1 end
  if to > lines then from = from - (to - lines); to = lines end
  local i = 1
  local maxwidth = 0
  for line in build:gmatch("[^\n]+") do
    if (i >= from and i <= to) or (flags.stickyloops and sticky[i]) then
      finalout = finalout..(sel and (i == sel and "> " or "  ") or "")..indent(i, to).." │ "..line.."\n"
      maxwidth = math.max(maxwidth, #line)
    end
    i = i + 1
  end

  finalout = finalout..("─"):rep(3 + #tostring(to)).."┴"..("─"):rep(maxwidth + 2).."\nIndexes:\n"
  for i,v in ipairs(ancestors) do
    if i > #ancestors-flags.maxindexes and i > 1 then
      if v.x ~= "" then
        finalout = finalout..indent(v.x.."*", indmax.."*").." = "..v.cur.." of "..v.max.."\n"
      elseif not flags.hideunlabeled then
        finalout = finalout..indent("*", indmax.."*").." = "..v.cur.." of "..v.max.."\n"
      end
    end
  end

  finalout = finalout..("─"):rep(6 + #tostring(to) + maxwidth).."\nAccumulators:\n"
  local maxacc = 0
  local maxval = 0
  local markval = {}
  local referenced = {}
  local rows = {}
  for i in pairs(pointers) do
    referenced[i] = true
    maxacc = math.max(maxacc, i)
    maxval = math.max(maxval, accumulators[i] or 0)
  end
  for i,v in pairs(accumulators) do
    maxacc = math.max(maxacc, i)
    maxval = math.max(maxval, v)
  end
  for i in pairs(derefpointers) do
    local acc = parseamount(i)
    local mark = parseamount(i:sub(2))
    markval[mark] = accumulators[acc] or 0
    referenced[acc] = true
    maxacc = math.max(maxacc, acc)
    maxval = math.max(maxval, accumulators[acc] or 0)
  end
  local maxrow = 0
  for i=0, maxacc do
    local row = math.floor(i / 10)
    local pos = i % 10
    rows[row] = rows[row] or {}
    if not flags.hidegarbage or markval[i] or referenced[i] or pointers[tostring(i)] then
      maxrow = math.max(maxrow, row)
      rows[row][pos] = string.format("%0"..#tostring(maxval).."d", accumulators[i] or 0)
      rows[row].has = true
      if markval[i] then
        rows[row][pos] = rows[row][pos]..string.format("→%0"..#tostring(maxval).."d", markval[i])
      else
        rows[row][pos] = rows[row][pos]..(" "):rep(#tostring(maxval) + 1)
      end
    end
  end
  for i=0, maxrow do
    local v = rows[i]
    if v and v.has then
      finalout = finalout..indent(i*10, maxrow*10).." │ "
      for j=0, 9 do
        if v[j] then finalout = finalout..v[j].." "
        else finalout = finalout..(" "):rep(#tostring(maxval) * 2 + 2) end
      end
      finalout = finalout.."\n"
    end
  end
  
  finalout = finalout.."\n"..("─"):rep(6 + #tostring(to) + maxwidth).."\nInput:\n"
  for i=inputbit, math.min(inputbit+flags.inputbytes-1, #input) do
    local c = input:byte(i)
    if flags.inputbytetype == "number" then
      finalout = finalout..string.format("%03d", c).." "
    elseif flags.inputbytetype == "bits" then
      local bin = ""
      for i=1, 8 do
        bin = (c % 2 == 1 and "1" or "0")..bin
        c = math.floor(c / 2)
      end
      finalout = finalout..bin.." "
    elseif flags.inputbytetype == "hex" then
      finalout = finalout..string.format("%02x", c).." "
    elseif flags.inputbytetype == "utf8" then
      finalout = finalout..string.char(c)
    end
  end

  finalout = finalout.."\n"..("─"):rep(6 + #tostring(to) + maxwidth).."\n"..out:sub(-flags.maxoutbytes)
  return "\x1B[2J\x1B[H"..finalout
end
  
function rcsearch(from, tag)
  if from.x ~= "" and parseamount(from.x) == parseamount(tag) then return from end
  if from == commands then return nil end
  return rcsearch(from.parent, tag)
end
function run(loop)
  loop.cur = 0
  local amount = parseamount(loop.n)
  loop.max = amount
  if flags.debug then
    print(progdump(commands, 0, loop.parseline - flags.linesup, loop.parseline + flags.linesdown, loop.parseline, loop))
    if not flags.autocycle then io.read()
    elseif tonumber(flags.autocycle) then os.execute("sleep "..flags.autocycle) end -- pause
  end
  while loop.cur < amount do
    loop.cur = loop.cur + 1
    for _,v in ipairs(loop) do
      if v.type ~= "loop" then
        local retvalue = nil
        local doreturn = false
        local dobreak = false
        if v.type == "+" then
          local target, increment = parseamount(v.x), parseamount(v.n)
          accumulators[target] = (accumulators[target] or 0) + increment
        elseif v.type == "&" then
          local get = rcsearch(loop, v.x)
          if get then
            retvalue = function(l) return l == get and "break" or true end
            if get == loop then dobreak = true
            else doreturn = true end
            if doreturn then loop.cur = 0 end
          end
        elseif v.type == "@" then -- one byte
          ioprompt()
          accumulators[parseamount(v.x)] = input:byte(inputbit)
          inputbit = inputbit + 1
        elseif v.type == "%" then
          local value = parseamount(v.n)
          if flags.debug then out = out..string.char(value % 256)
          else io.write(string.char(value % 256)) end
        elseif v.type == "#" then
          local value = parseamount(v.n)
          if flags.debug then out = out..value
          else io.write(tostring(value)) end
        elseif v.type == "~" then
          flags.debug = not flags.debug
        end
        if flags.debug then
          print(progdump(commands, 0, v.parseline - flags.linesup, v.parseline + flags.linesdown, v.parseline, loop))
          if not flags.autocycle then io.read()
          elseif tonumber(flags.autocycle) then os.execute("sleep "..flags.autocycle) end
        end
        if doreturn then return retvalue end
        if dobreak then break end
      else
        local outer = run(v) or function() return false end
        if outer(loop) == true then return outer end
        if outer(loop) == "break" then break end
      end
    end
  end
end
if flags.dump then
  print(progdump(commands))
end
if flags.parserdump then
  print(dump(commands))
end
run(commands)
