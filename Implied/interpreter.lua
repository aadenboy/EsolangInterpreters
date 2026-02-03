local file = io.open("field.txt", "r")
local field = file:read("*a")
file:close()

local tiles = {}
local x, y = 1, 1
for i=1, #field do
  local char = field:sub(i, i)
  if char == "\n" then
    tiles[y] = tiles[y] or {}
    x = 1
    y = y + 1
  else
    tiles[y] = tiles[y] or {}
    tiles[y][x] = char
    x = x + 1
  end
end
function get(x, y)
  local tile = tiles[y] and tiles[y][x] or nil
  if tile == "1" then return true
  elseif tile == "0" then return false
  else return nil end
end

function func(a, b, f)
  if a ~= true and a ~= false then return b end
  if b ~= true and b ~= false then return a end
  return f
end
function imply(a, b) return func(a, b, not a or b) end
function nimply(a, b) return func(a, b, a and not b) end
function conimply(a, b) return func(a, b, not b or a) end
function connimply(a, b) return func(a, b, b and not a) end
local funcs = {
  i = imply,
  I = nimply,
  c = conimply,
  C = connimply
}

function state(r)
  local out = "\x1B[2J\x1B[H"
  for y,col in ipairs(tiles) do
    for x,char in ipairs(col) do
      out = out..char
    end
    out = out.."\n"
  end
  print(out)
  if r then io.read() end
end
function runner(x, y)
  local char = tiles[y] and tiles[y][x]
  if char and char:match("[iIcC]") then
    local l = get(x-1, y)
    local r = get(x+1, y)
    local u = get(x, y-1)
    local d = get(x, y+1)
    local total =
      (l ~= nil and 1 or 0) +
      (r ~= nil and 1 or 0) +
      (u ~= nil and 1 or 0) +
      (d ~= nil and 1 or 0)
    local f = funcs[char]
    print(l, r, u, d)
    print(f(l, r), f(f(l, r), u), f(f(f(l, r), u), d))
    local result = f(f(f(l, r), u), d)
    anyactive = anyactive or total >= 2
    if total < 2 then result = nil end
    if result == true then tiles[y][x] = "!"
    elseif result == false then tiles[y][x] = "@"
    end
  end
end
local anyactive = true
while anyactive do
  anyactive = false
  state(true)
  local torun = {}
  for y,col in ipairs(tiles) do
    for x,char in ipairs(col) do
      if char == "!" or char == "@" then
        anyactive = true
        tiles[y][x] = char == "!" and "1" or "0"
        table.insert(torun, {x-1, y})
        table.insert(torun, {x+1, y})
        table.insert(torun, {x, y-1})
        table.insert(torun, {x, y+1})
      end
    end
  end
  for i,v in ipairs(torun) do
    runner(v[1], v[2])
  end
end
state()
