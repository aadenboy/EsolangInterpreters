local file = io.open(arg[1], "r")
assert(file, "File not found")
local form = file:read("*a")
file:close()
local defs = {}
form = form:gsub("(%w+)=([^\n]+)", function(a, b) defs[a] = b;  return "" end)
           :gsub("(%w+)=",         function(a)    defs[a] = ""; return "" end)
           :gsub("%w+", defs):gsub("^%s*(.-)%s*$", "%1")
repeat
  print(form)
  form, amount = form:gsub("(%b())(%b())(.*)$", function(a, b, c)
    return b:sub(2, -2):gsub("%(%)", a:sub(2, -2))..c
  end)
until amount == 0
