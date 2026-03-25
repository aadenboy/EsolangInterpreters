local file = io.open(arg[1], "r")
assert(file, "File not found")
local code = file:read("*a")
file:close()

code = ";"..code:gsub("//[^\n]+", ""):gsub(";", ";;")..";" -- preprocessing
local escapedcode = code:gsub("\\.", "__") -- to make string processing easier
local load = loadstring or load
function formatstr(from, to)
   local str = code:sub(to and from or 0, from and to and (to - 1) or 0) -- empty string if nil
   local func = load("return \""..str.."\"") -- lazy way of doing this
   if not func then error("String "..str.." is malformed") end
   return func()
end

local defs = {}
for _, deffrom, defto, _, valuefrom, valueto in escapedcode:gmatch(";%s*define%s*(['\"])()[^'\"]+()%1%s*=>%s*(['\"])()[^'\"]+()%4%s*;") do
   local def = formatstr(deffrom, defto)
   def = def:gsub("[%(%)%[%]%^%$%+%-%*%?%.%%]", "%%%0")
   local value = formatstr(valuefrom, valueto)
   value = value:gsub("%%", "%%%%")
   table.insert(defs, {pattern = def, replacement = value})
end

local _, inputfrom, inputto = escapedcode:match(";%s*input%s*(['\"])().-()%1%s*;")
local input = formatstr(inputfrom, inputto)

local limits = {}
for _, limitfrom, limitto in escapedcode:gmatch(";%s*limit%s*(['\"])().-()%1%s*;") do
   limits[formatstr(limitfrom, limitto)] = true
end

print(input)
while not limits[input] do
   io.read()
   for i,v in ipairs(defs) do
      input = input:gsub(v.pattern, v.replacement)
   end
   print(input)
end
