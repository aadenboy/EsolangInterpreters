local gargs = {}
local flags = {
    debug = false,      -- visually show the program
    emptyinput = false  -- mark input as being empty
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

local file = io.open(gargs[1], "r")
assert(file, "No file "..gargs[1])
local program = file:read("*a")
file:close()

local tape = {[0] = 0}
local p = 0
local iob = false

assert(not flags.debug or gargs[2] or flags.emptyinput, "Debug requires an input file or --emptyinput flag")
local input = ""
local output = ""
if gargs[2] then
    local infile = io.open(gargs[2], "r")
    input = infile:read("*a")
    infile:close()
end

local i = 1

function debug()
    local s = "== Program ==\n"..program:sub(i, i+50).."\n== Input ==\n"..input:sub(1, 50).."\n"
    local s2 = ""
    for i=1, math.min(20, #input) do
        s = s..string.format("%03d ", input:byte(i))
        s2 = s2..string.format("%02x ", input:byte(i))
    end
    s = s.."\n"..s2.."\n== Tape ==\n"
    local max = ""
    for i=0, #tape do
        if #(tape[i].."") > #max then max = tape[i].."" end
    end
    for i=0, #tape do -- yawn
        s = s..(p == i and " > " or "   ")..string.format("%0"..#max.."d", tape[i])
        if i % 10 == 9 and i ~= #tape then s = s.."\n" end
    end
    s = s.."\n== Output ==\n"..output:sub(-50, -1).."\n"
    s2 = ""
    for i=math.max(#output-49, 1), #output do
        s = s..string.format("%03d ", output:byte(i))
        s2 = s2..string.format("%02x ", output:byte(i))
    end
    s = s.."\n"..s2
    print("\x1B[H\x1B[2J"..s)
    io.read()
end

while true do
    if flags.debug then debug() end
    local c = program:sub(i, i)
    if c == ">" then
        p = p + 1
        tape[p] = (tape[p] or 0) + 1
    elseif c == "<" then
        tape[p] = tape[p] + 1
        p = 0
    elseif c == "/" then
        tape[p] = tape[p] + 1
        i = tape[p] ~= (tape[p+1] or 0) and i+(program:sub(i+1)..program):match("()/") or i
    elseif c == "~" then
        iob = not iob
    elseif c == "." and iob and (input ~= "" or not (flags.emptyinput or gargs[2])) then
        if input == "" then input = io.read().."\0" end
        tape[p] = tape[p] + input:byte(1)
        input = input:sub(2)
    elseif c == "." and not iob then
        output = output..string.char(tape[p] % 256)
        io.write(string.char(tape[p] % 256))
    end
    i = (i % #program) + 1
end
if flags.debug then debug() end
