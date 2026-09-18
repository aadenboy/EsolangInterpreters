local utf8 = require("utf8")

local gargs = {}
local flags = {
    debug = false,      -- visually show the pointers moving through the program
    emptyinput = false, -- mark input as being empty
    padup = 7,          -- the amount of characters to show above each pointer
    paddown = 7,        -- the amount of characters to show below each pointer
    padleft = 12,       -- the amount of characters to show to the left of each pointer
    padright = 12,      -- the amount of characters to show to the right of each pointer
    showall = false,    -- ignore cropping and show the entire program at once instead
    seed = os.time(),   -- the seed used for randomization
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
math.randomseed(flags.seed)
assert(not flags.debug or gargs[2] or flags.emptyinput, "Debug requires an input file or --emptyinput flag")
assert(gargs[1], "Expected input")
local file = io.open(gargs[1], "r")
assert(file, "No file "..gargs[1])

local program = {}
function set(x, y, v)
    program[x] = program[x] or {}
    program[x][y] = v
end
function get(x, y) return program[x] and program[x][y] end
local initx, width = 0, 0
local x, y = 0, 0
local char = file:read(1)
while char do
    if char ~= "\n" then
        if char ~= " " then set(x, y, char) end
        initx = y == 0 and x or initx
        width = math.max(x, width)
        x = x + 1
    else
        x = 0
        y = y + 1
    end
    char = file:read(1)
end
local height = y
file:close()

local input = ""
if gargs[2] then
    local infile = io.open(gargs[2], "r")
    input = infile:read("*a")
    infile:close()
end

local tickets = 1 -- total
local pointers = {
    {x = initx, y = 0, tickets = 1, a = 0, dir = {-1, 1}}
}
local tree = {value = 0, weights = 0, children = {}, parent = nil, weight = 0}
local ptree = tree

local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
function treedumper(n, i)
    local s = i..": "..n.value.." ("..n.weight..")"..(ptree == n and " <-" or "").."\n"
    for j,v in ipairs(n.children) do
        s = s..treedumper(v, "  "..i..alphabet:sub(j, j))
    end
    return s
end

local dbout = ""
while #pointers > 0 do
    if flags.debug then
        local s = ""
        local s2 = ""
        local claimed = {}
        local minx, maxx = width, 0
        local miny, maxy = height, 0
        for i,v in ipairs(pointers) do
            s2 = s2.."pos: "..v.x..", "..v.y.."\ttickets: "..v.tickets.."\ta: "..v.a.."\tdir: "..v.dir[1]..", "..v.dir[2].."\n"
            claimed[v.x] = claimed[v.x] or {}
            claimed[v.x][v.y] = true
            if not flags.showall then
                miny = math.min(miny, v.y - flags.padup)
                maxy = math.max(maxy, v.y + flags.paddown)
                minx = math.min(minx, v.x - flags.padleft)
                maxx = math.max(maxx, v.x + flags.padright)
            end
        end
        if flags.showall then
            minx, maxx = 0, width
            miny, maxy = 0, height
        end
        for y=miny, maxy do
            for x=minx, maxx do
                s = s..(claimed[x] and claimed[x][y] and "@" or get(x, y) or " ")
            end
            s = s.."\n"
        end
        print("\x1B[H\x1B[2JInput: "..input.."\nOutput: "..dbout.."\n"..s..s2..treedumper(tree, ""))
        io.read()
    end
    local choice = math.random(1, tickets)
    local p, pi
    for i,v in ipairs(pointers) do
        choice = choice - v.tickets
        if choice <= 0 then
            p, pi = v, i
            break
        end
    end
    local char = get(p.x, p.y)
    local extra
    if char == "*" then
        tickets = tickets - p.tickets
        table.remove(pointers, pi)
        p = nil
    elseif char == "|" or char == "-" then
        extra = {x = p.x, y = p.y, tickets = p.tickets, a = p.a, dir = {
            char == "|" and -p.dir[1] or p.dir[1],
            char == "-" and -p.dir[2] or p.dir[2]
        }}
        tickets = tickets + p.tickets
        table.insert(pointers, extra)
    elseif (char == "(" or char == ")") and ptree.value == 0 then
        p.dir = {
            char == "(" and -p.dir[2] or p.dir[2],
            char == ")" and -p.dir[1] or p.dir[1]
        }
    elseif char == "+" then
        p.tickets = p.tickets + 1
        tickets = tickets + 1
    elseif char == "/" and ptree.parent then
        ptree = ptree.parent
    elseif char == "\\" and ptree.weights > 0 then
        local chosen = math.random(1, ptree.weights)
        for i,v in ipairs(ptree.children) do
            chosen = chosen - v.weight
            if chosen <= 0 then
                ptree = v
                break
            end
        end
    elseif char == "," then
        table.insert(ptree.children, {value = 0, weights = 0, children = {}, parent = ptree, weight = p.a})
        ptree.weights = ptree.weights + p.a
    elseif char == "." then
        ptree.value = p.a
    elseif char == ":" then
        p.a = math.max(ptree.value, 0)
    elseif char == ";" then
        set(p.x, p.y, utf8.char(ptree.value))
    elseif char == ">" then
        p.a = p.a + 1
    elseif char == "<" and p.a > 0 then
        p.a = p.a - 1
    elseif char == "!" then
        io.write(utf8.char(ptree.value))
        dbout = dbout..utf8.char(ptree.value)
    elseif char == "?" and (flags.emptyinput or (input == "" and gargs[2])) then
        ptree.value = 0
    elseif char == "?" then
        if input == "" then
            input = io.read().."\0"
        end
        ptree.value = utf8.codepoint(input:sub(1, utf8.offset(input, 2) - 1))
        input = input:sub(utf8.offset(input, 2))
    end
    if p then
        p.x = (p.x + p.dir[1]) % (width + 1)
        p.y = (p.y + p.dir[2]) % (height + 1)
    end
    if extra then
        extra.x = (extra.x + extra.dir[1]) % (width + 1)
        extra.y = (extra.y + extra.dir[2]) % (height + 1)
    end
end