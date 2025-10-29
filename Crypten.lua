if not arg[1] then error("No input file specified") end
local file = io.open(arg[1], "r")
assert(file, "Input file not found")
local text = file:read("*a")
file:close()

function fromutf8(s, i)
  if i == nil then i = 1 end
  local c = s:byte(i)
  if c >= b"11000000" and c < b"11100000" then
    return shl(c % 0x20, 6) + (text:byte(i+1) % 0x40), 2
  elseif c >= b"11100000" and c < b"11110000" then
    return shl(c % 0x10, 12) + shl(text:byte(i+1) % 0x40, 6) + (text:byte(i+2) % 0x40), 3
  elseif c >= b"11110000" and c < b"11111000" then
    return shl(c % 0x8, 18) + shl(text:byte(i+1) % 0x40, 12) + shl(text:byte(i+2) % 0x40, 6) + (text:byte(i+3) % 0x40), 4
  else return c, 1 end
end
function toutf8(cp) -- https://stackoverflow.com/a/26237757
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

function b(n) return tonumber(n, 2) end
function shl(n, b) return n * 2^b end
function shr(n, b) return math.floor(n / 2^b) end
local bytes = {}
local i = 1
repeat
  local c, ni = fromutf8(text, i)
  i = i + ni
  for i=1, 4 do
    local n = c % 0x10
    c = shr(c, 4)
    table.insert(bytes, n)
  end
until i >= #text

local matrix = {}
local x, y = 0, 0
function get(nx, ny) return matrix[(nx or x)..(ny or y)] or 0 end
function set(n, nx, ny) matrix[(nx or x)..(ny or y)] = n end
i = 1
repeat
  local n = bytes[i]
  i = i + 1
      if n == 1 then set(get() + 1)
  elseif n == 2 then set(get() - 1)
  elseif n == 3 then x = x - 1
  elseif n == 4 then y = y - 1
  elseif n == 5 then x = x + 1
  elseif n == 6 then y = y + 1
  elseif n == 7 then x = 0; y = 0
  elseif n == 8 and get() == 0 then
    repeat i = i - 1 until bytes[i] == 9 or i < 1
    if i < 1 then break end
  elseif n == 10 then
    local input = io.read()
    set(tonumber(input) or 0)
    if not tonumber(input) then print("THAT AIN'T A NUMBER, SONNY") end
  elseif n == 11 then io.write(toutf8(get()))
  elseif n == 12 then io.write(tostring(get()))
  elseif n == 13 then set(get(x, y+1) + get(), x, y+1); set(0)
  elseif n == 14 then set((fromutf8(io.read(), 1)))
  elseif n == 15 then break end
until i >= #bytes
