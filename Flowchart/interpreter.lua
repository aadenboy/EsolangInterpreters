local gargs = {}
local flags = {
    debug = false,      -- visually show the pointers moving through the program
    binary = false,     -- treat I/O as bits (characters 0/1) instead of bytes
    emptyinput = false, -- mark input as being empty
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

assert(gargs[1], "Expected file")
local file = io.open(arg[1], "r")
assert(file, gargs[1].." not found")
local chart = file:read("*a")
file:close()

assert(not flags.debug or gargs[2] or flags.emptyinput, "Debug mode requires an input file; set the --emptyinput flag if there is none")
local ifile = gargs[2] and io.open(gargs[2], "r")
local input = ifile and ifile:read("*a")
local bit, ilen = 0, 0
if ifile then ifile:close() end
local output = ""

local nodes = { -- RULD
    ["─"] = {type = "path", true,  false, true,  false          },
    ["│"] = {type = "path", false, true,  false, true           },
    ["└"] = {type = "path", true,  false, false, true           },
    ["┘"] = {type = "path", false, false, true,  true           },
    ["┐"] = {type = "path", false, true,  true,  false          },
    ["┌"] = {type = "path", true,  true,  false, false          },
    ["├"] = {type = "path", true,  true,  false, true,  t = true},
    ["┴"] = {type = "path", true,  false, true,  true,  t = true},
    ["┤"] = {type = "path", false, true,  true,  true,  t = true},
    ["┬"] = {type = "path", true,  true,  true,  false, t = true},
    ["┼"] = {type = "path", true,  true,  true,  true,  t = true},
    ["( )"] = {type = "node"},
    ["(( ))"] = {type = "end"},
    ["[ ]"] = {type = "set"},
    ["{ ]"] = {type = "set", v = 0},
    ["[ }"] = {type = "set", v = 1},
    ["{ }"] = {type = "set", v = -1},
    ["< >"] = {type = "switch"},
    ["/ /"] = {type = "input"},
    ["\\ \\"] = {type = "output"},
    ["\\[ ]/"] = {type = "push", d = "top"},
    ["/[ ]\\"] = {type = "push", d = "bottom"},
    ["\\{ }/"] = {type = "pop", d = "top"},
    ["/{ }\\"] = {type = "pop", d = "bottom"},
    ["< ]"] = {type = "deque", d = "left"},
    ["[ >"] = {type = "deque", d = "right"},
}
for i,v in pairs(nodes) do v.i = i end
local dir = {
    {x = 1, y = 0, s = {"→", "⇨", "⮕"}},
    {x = 0, y = 1, s = {"↓", "⇩", "⬇"}},
    {x = -1, y = 0, s = {"←", "⇦", "⬅"}},
    {x = 0, y = -1, s = {"↑", "⇧", "⬆"}}
}
local objects = {}
function set(x, y, v)
    objects[x] = objects[x] or {}
    objects[x][y] = {x = x, y = y, v = v}
end
function get(x, y)
    x = math.floor(x)
    y = math.floor(y)
    return objects[x] and objects[x][y]
end
function getpaths(n, dir) -- return front, right, left, back
    local x, y, w = n.x, n.y, n.v.type == "path" and 1 or #n.v.i
    local px, nx, py, ny = get(x+w,y), get(x-1,y), get(x+(w-1)/2,y+1), get(x+(w-1)/2,y-1)
    px = px and (px.v.type ~= "path" or px.v[3]) and (n.v.type == "path" or px.v.type == "path") and px
    nx = nx and (nx.v.type ~= "path" or nx.v[1]) and (n.v.type == "path" or nx.v.type == "path") and nx
    py = py and (py.v.type ~= "path" or py.v[4]) and (n.v.type == "path" or py.v.type == "path") and py
    ny = ny and (ny.v.type ~= "path" or ny.v[2]) and (n.v.type == "path" or ny.v.type == "path") and ny
    if n.v.type == "path" then
        px = n.v[1] and px
        py = n.v[2] and py
        nx = n.v[3] and nx
        ny = n.v[4] and ny
    end
        if dir == 1 then return px, py, ny, nx
    elseif dir == 2 then return py, nx, px, ny
    elseif dir == 3 then return nx, ny, py, px
    elseif dir == 4 then return ny, px, nx, py end
end
function d(a) return (a-1)%4+1 end

local pointers = {}
local pn = 0
local deques = {}
local buffer, blen = 0, 0
function np(x, y, d) table.insert(pointers, {x = x, y = y, d = d, pn = pn, r = -1, p = {}, q = 0}); pn = pn + 1 end

local i = 1
local x, y = 0, 0
local mx = 0
local minx, miny, minnode = math.huge, math.huge
repeat
    if chart:sub(i, i) == " " then x = x + 1; i = i + 1
    elseif chart:sub(i, i) == "\n" then x = 0; y = y + 1; i = i + 1;
    else
        local got = false
        for n,v in pairs(nodes) do
            if chart:sub(i, i+#n-1) == n then
                if v.type == "node" and (x < minx or (x == minx and y < miny)) then
                    minx = x
                    miny = y
                    minnode = v
                end
                if v.type == "path" then set(x, y, v); x = x + 1
                else for i=1, #n do set(x, y, v); x = x + 1 end end
                i = i + #n
                got = true
                break
            end
        end
        if not got then i = i + 1 end
    end
    mx = math.max(mx, x)
until i > #chart
if minnode then
    local f, r, l, b = getpaths(get(minx, miny), 1)
    if f then np(minx, miny, 1) end
    if r then np(minx, miny, 2) end
    if b then np(minx, miny, 3) end
    if l then np(minx, miny, 4) end
end

function evalpath(v, node)
    local ldir = (node.v.type ~= "path" or node.v.t) and v.p[node]
    ldir = ldir and d(ldir-2) ~= v.d and ldir
    if not ldir then
        local pf, pr, pl = getpaths(node, v.d)
        assert(pf or pr or pl or node.v.type == "end", "Pointer stuck at "..v.x..", "..v.y.." with a direction of "..v.d)
        v.p[node] = d((pf and v.d) or (pr and v.d+1) or v.d-1)
    end
    v.d = v.p[node]
end
function binary(n)
    if n == "" then return "" end
    if type(n) == "string" then n = n:byte(1) or 0 end
    local s = ""
    for i=1, 8 do
        s = math.floor(n % 2)..s
        n = math.floor(n / 2)
    end
    return s
end

function debug()
    local s = "\x1B[H\x1B[2J"
    if not flags.binary then
        local input = input or ""
        s = s..binary(bit):sub(8-ilen+1)..("_"):rep(8-ilen)
        for i=5, 1, -1 do s = s.." "..binary(input:sub(i)) end
        s = s.."\n"..input.."\n"
    else s = s..input:sub(1, 64):gsub("[^1]", "0").."\n" end
    for py=0, y do
        local px = 0
        while px <= mx do
            local at = get(px, py)
            local anypointer
            for i,v in ipairs(pointers) do
                if v.x == px and v.y == py then anypointer = v break end
            end
            s = s..(at and at.v.i:gsub(" ", anypointer and dir[anypointer.d].s[anypointer.r+2] or " ") or " ")
            px = px + ((not at or at.v.type == "path") and 1 or #at.v.i)
        end
        s = s.."\n"
    end
    if not flags.binary then
        s = s..binary(buffer):sub(8-blen+1)..("_"):rep(8-blen)
        for i=#output, math.max(#output-4, 1), -1 do s = s.." "..binary(output:sub(i)) end
        s = s.."\n"..output.."\n"
    else s = s..output:sub(-64).."\n" end
    local q, qc = {}, {}
    for i,v in ipairs(pointers) do
        local at = get(v.x, v.y)
        s = s..(at and at.v.i or "???"):gsub(" ", dir[v.d].s[v.r+2]).." {"..v.x..", "..v.y.."} -> "..v.q.."\n"
        qc[v.q] = true
    end
    for i,v in pairs(deques) do
        if qc[i] or #v > 0 then
            local qs = ""
            for o,b in ipairs(v) do qs = qs..(b == -1 and "_" or b) end
            table.insert(q, {i, "Q"..i..": "..qs})
        end
    end
    table.sort(q, function(a, b) return a[1] < b[1] end)
    for i,v in ipairs(q) do s = s..v[2].."\n" end
    print(s)
    io.read()
end

while #pointers > 0 do
    if flags.debug then debug() end
    for i,v in ipairs(pointers) do
        local node = get(v.x, v.y)
        evalpath(v, node)
        local seen = {}
        repeat
            node = getpaths(node, v.d)
            assert(node, "Pointer at "..v.x..", "..v.y.." has no node?")
            assert(not seen[node], "Pointer at "..v.x..", "..v.y.." is stuck in a loop")
            seen[node] = true
            v.x, v.y = node.x, node.y
            if node.v.type == "path" then evalpath(v, node) end
        until node.v.type ~= "path"
        if v.d == 2 or v.d == 4 then v.x = v.x - (#node.v.i-1)/2
        elseif v.d == 3 then v.x = v.x - #node.v.i + 1 end
    end
    table.sort(pointers, function(a, b)
        if a.x == b.x and a.y == b.y then return a.pn < b.pn
        elseif a.x == b.x then return a.y < b.y
        else return a.x < b.x end
    end)
    local i, max = 1, #pointers
    repeat
        local v = pointers[i]
        local node = get(v.x, v.y)
        if node.v.type == "node" then
            local f, a, b = getpaths(node, v.d)
            if f and a then np(v.x, v.y, d(v.d+1)) end
            if f and a and b then np(v.x, v.y, d(v.d-1)) end
            v.p[node] = nil
        elseif node.v.type == "end" then
            table.remove(pointers, i)
            max = max - 1
        elseif node.v.type == "set" then
            v.r = node.v.v or (v.r < 1 and 1 or 0)
        elseif node.v.type == "switch" then
            local f, cw, ccw = getpaths(node, v.d)
            v.p[node] = (v.r == -1 and f and v.d) or (v.r == 0 and cw and d(v.d+1)) or (v.r == 1 and ccw and d(v.d-1))
        elseif node.v.type == "input" then
            if not input and not flags.emptyinput then input = io.read() end
            if #input > 0 and flags.binary then
                v.r = input:sub(1, 1) == "1" and 1 or 0
                input = input:sub(2)
            elseif ilen == 0 and #input > 0 then
                bit = math.floor(input:byte(1) / 2)
                ilen = 7
                v.r = input:byte(1) % 2
                input = input:sub(2)
            elseif ilen == 0 and ifile then v.r = -1
            elseif ilen == 0 then v.r = -1; input = nil
            else v.r = bit % 2; bit = math.floor(bit / 2); ilen = ilen - 1 end
        elseif node.v.type == "output" then
            buffer = buffer + math.max(v.r, 0) * 2^blen
            blen = blen + 1
            if blen == 8 then
                io.write(string.char(buffer))
                output = output..string.char(buffer)
                buffer = 0
                blen = 0
            end
            if flags.binary then
                io.write(tostring(math.floor(buffer)))
                output = output..math.floor(buffer)
                buffer = 0
                blen = 0
            end
        elseif node.v.type == "push" then
            deques[v.q] = deques[v.q] or {}
            table.insert(deques[v.q], node.v.d == "top" and #deques[v.q]+1 or 1, v.r)
        elseif node.v.type == "pop" then
            v.r = deques[v.q] and table.remove(deques[v.q], node.v.d == "top" and #deques[v.q] or 1) or -1
        elseif node.v.type == "deque" then
            v.q = v.q + (node.v.d == "left" and -1 or 1)
        end
        if node.v.type ~= "end" then i = i + 1 end
    until i > max
    
    --print(s)
end
if flags.debug then debug() end