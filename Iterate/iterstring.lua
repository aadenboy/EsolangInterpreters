local escapes = {
  [7] = "\\a",
  [8] = "\\b",
  [9] = "\\t",
  [10] = "\\n",
  [11] = "\\v",
  [12] = "\\f",
  [13] = "\\r",
  [27] = "\\e"
}
function unescape(s)
  return s:gsub(".", function(a)
    if a:byte() < 32 then
      return escapes[a:byte()] or a:byte()
    else return a end
  end)
end
function patternsafe(s)
  return s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end
function loopify(s, index, indent)
  indent = indent or ""
  local out = ""
  local i = 1
  repeat
    local c = s:sub(i, i)
    local psc = patternsafe(c)
    if s:sub(i):match(psc.."+[^"..psc.."]+"..psc.."+") then
      local pre, inner, suff = s:sub(i):match("("..psc.."+)([^"..psc.."]+)("..psc.."+)")
      out = out..indent.."*1< ("..index.."*)"..c:byte().."< *~n< &"..index.." > "..("~@ "):rep(#pre).." // "..unescape(pre).."\n"
               ..loopify(inner, index + 1, indent.."  ")
               ..indent..("~@"):rep(#suff).." ! > > // "..unescape(suff).."\n"
      i = i + #pre + #inner + #suff
    else
      local rep = s:sub(i):match(psc.."+")
      out = out..indent.."*1< ("..index.."*)"..c:byte().."< *~n< &"..index.." > "..("~@ "):rep(#rep).."! > > // "..unescape(rep).."\n"
      i = i + #rep
    end
  until i > #s
  return out
end
local out = loopify(io.read(), 1, "  ")
local max = 0
for c in out:gmatch("[^\n]+//") do
  max = math.max(max, #c)
end
out = out:gsub("[^\n]+//", function(a)
  return a:sub(1, -3)..(" "):rep(max - #a).."//"
end)
local f = io.open("out.it", "w")
f:write(out)
f:close()

--[[if s:sub(i):match("%$%d+") then
  local first = s:sub(i):match("%$%d+")
  local after = s:sub(#first + 1)
  local pre = first
  while after:sub(1, #first) == first do
    pre = pre..after:sub(1, #first)
    after = after:sub(#first + 1)
  end
  local inner = after:match("^(.-)"..first)
  if inner then
    after = after:sub(#inner + 1)
    local suff = ""
    while after:sub(1, #first) == first do
      suff = suff..after:sub(1, #first)
      after = after:sub(#first + 1)
    end
    out = out..indent.."*1< ("..index.."*)="..first:sub(2).."< *~n< &"..index.." > "..("@ "):rep(#pre/#first).." // ("..first:sub(2).."*)\n"
             ..loopify(inner, index + 1, indent.."  ")
             ..indent..("@ "):rep(#suff/#first).."! > > // ("..first:sub(2).."*)\n"
    print(pre..inner..suff, #pre, #inner, #suff)
    i = i + #pre + #inner + #suff
    print(s:sub(i))
  else
    out = out..indent.."*1< ("..index.."*)="..first:sub(2).."< *~n< &"..index.." > "..("@ "):rep(#pre).."! > > // ("..first:sub(2).."*)\n"
    i = i + #pre
  end
else]]
