-- to support lua 5.1+
function shiftr(x, y) return math.floor(x / 2^y) end
function shiftl(x, y) return (x * 2^y) % 256 end
function toutf8(num)
    if num <= 0x7F then
        return string.char(num)
    elseif num <= 0x7FF then
        return string.char(0xC0 + shiftr(num, 6), 0x80 + (num % 0x3F))
    elseif num <= 0xFFFF then
        return string.char(0xE0 + shiftr(num, 12), 0x80 + shiftr(num % 0x1000, 6), 0x80 + (num % 0x3F))
    elseif num <= 0x10FFFF then
        return string.char(0xF0 + shiftr(num, 18), 0x80 + shiftr(num % 0x40000, 12), 0x80 + shiftr(num % 0x1000, 6), 0x80 + (num % 0x3F))
    end
end

local prog = arg[1] or io.read()
local file = io.open(prog, "r")
if not file then error("File not found") end
local code = file:read("*a")
file:close()
local inputs = {}
local flags = {
    useio = false,
    dump = false,
    parserdump = false,
    debug = false,
    autocycle = false,
    linesup = 5,
    linesdown = 5,
}
for i=2, #arg do
    if arg[i]:match("^%d+$") then
        table.insert(inputs, tonumber(arg[i]))
    elseif arg[i]:match("^%-%-[^=]+=%-?%d*%.?%d+") then
        local name, value = arg[i]:match("^%-%-(.-)=(%-?%d*%.?%d+)")
        flags[name] = tonumber(value)
    elseif arg[i]:match("^%-%-") then
        flags[arg[i]:sub(3)] = true
    end
end
local useio = #inputs == 0 or flags.useio

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
           :gsub("[^()<>*0-9~ni=?%^!@&%$\n]", "") -- \n to preserve line numbers

local loops = {}
local current = {}
local labels = {}
local highestlabel = 0
local i = 1
function rcassert(from, tag)
    if tag == "" then return true end
    if from.labels[tag] then return false, from.labels[tag] end
    if from == loops[1] then return true end
    return rcassert(from.parent, tag)
end
function rcsearch(from, tag)
    if tag == "" then return end
    if from.label == tag then return from end
    if from == loops[1] then return from end
    return rcsearch(from.parent, tag)
end
local line = 1
local parseline = 1
repeat
    local s = code:sub(i)
    if s:match("^\n") then line = line + 1 end

    if s:match("^%(%*%).-<") and #loops == 0 then
        assert(s:match("^%(%*%)[^<]*%b<>"), "Unclosed loop at line "..line)
        loops[1] = {
            label = "^",
            amount = s:match("^%(%*%)(.-)%b<>"),
            commands = {},
            parent = {},
            n = 0, visits = 0,
            labels = {},
            line = line,
            parseline = parseline
        }
        current = loops[1]
        labels["^"] = 0
        highestlabel = 1
        i = i + s:match("^%(%*%).-()%b<>")
        parseline = parseline + 1
    elseif s:match("^%(%d+%*%).-<") then
        assert(s:match("^%(%d+%*%)[^<]*%b<>"), "Unclosed loop at line "..line)
        local loop = {
            label = s:match("^%((%d+)"),
            amount = s:match("^%(%d+%*%)(.-)%b<>"),
            commands = {},
            parent = current,
            n = 0, visits = 0,
            labels = {},
            line = line,
            parseline = parseline
        }
        local valid, previous = rcassert(loop.parent, loop.label)
        assert(valid, "Duplicate labels in the same scope are not allowed (label "..loop.label.." at line "..line..", previously defined at line "..(previous and previous.line or "")..")")
        for i,v in ipairs(loop.parent.labels or {}) do
            loop.labels[i] = v
        end
        labels[loop.label] = 0
        highestlabel = math.max(highestlabel, tonumber(loop.label))
        loop.labels[loop.label] = loop
        loop.parent.labels[loop.label] = loop
        table.insert(loops, loop)
        table.insert(current.commands, loop)
        current = loop
        i = i + s:match("^%(%d+%*%).-()%b<>")
        parseline = parseline + 1
    elseif s:match("^%*.-<") then
        assert(s:match("^%*[^<]*%b<>"), "Unclosed loop at line "..line)
        local loop = {
            label = "",
            amount = s:match("^%*(.-)%b<>"),
            commands = {},
            parent = current,
            n = 0, visits = 0,
            labels = {},
            line = line,
            parseline = parseline
        }
        table.insert(loops, loop)
        table.insert(current.commands, loop)
        current = loop
        i = i + s:match("^%*.-()%b<>")
        parseline = parseline + 1
    elseif s:match("^[!&]") then
        local kind = s:match('^(.)')
        local command = {
            type = kind,
            param = s:match("^"..kind.."(%d+)") or s:match("^"..kind.."(%^)"),
            line = line,
            parseline = parseline
        }
        table.insert(current.commands, command)
        i = i + 1 + #(command.param or "")
        parseline = parseline + 1
    elseif s:match("^[@~]") then
        local kind = s:match("^~") and "~@" or "@"
        local command = {
            type = kind,
            line = line,
            parseline = parseline
        }
        table.insert(current.commands, command)
        i = i + #kind
        parseline = parseline + 1
    elseif s:match("^%$[0-9%^]") then
        local kind = s:match('^(.)')
        local command = {
            type = "$",
            param = s:match("^%$(%d+)") or s:match("^%$(%^)"),
            line = line,
            parseline = parseline
        }
        table.insert(current.commands, command)
        i = i + 1 + #command.param
        parseline = parseline + 1
    elseif s:match("^>") then
        if #current.commands > 0 then parseline = parseline + 1 end
        current = current.parent
        i = i + 1
    else
        i = i + 1
    end
until i >= #code

current = loops[1]
if not current or current.label ~= "^" then return end

function loopamount(loop, first)
    if first == nil then first = true end
    local la = loop.amount
    if la:match("^%d+$") then
        return tonumber(la)
    elseif la == "i" then
        return math.huge
    elseif la == "?" then
        if first == true then
            loop.cache = useio and io.read() or inputs[1]
            if not useio then table.remove(inputs, 1) end
        end
        local num = tonumber(loop.cache) or 0
        return math.max(math.floor(num + 0.5), 0)
    elseif la == "n" then
        return loop.parent.n or 0
    elseif la:match("^n%d+$") or la == "n^" then
        for _,v in ipairs(loops) do if v.label == la:sub(2) then return v.n end end
    elseif la == "~n" then
        return loopamount(loop.parent or {}, false) - (loop.parent.n or 0)
    elseif la:match("^~n%d+$") or la == "~n^" then
        for _,v in ipairs(loops) do if v.label == la:sub(3) then return loopamount(v, false) - v.n end end
    elseif la:match("^=%d+$") or la == "=^" then
        return labels[la:sub(2)] or 0
    end
    return 0
end

local out = ""
local function indent(num, max)
    return (" "):rep(#tostring(max) - #tostring(num))..num
end
function progdump(loop, depth, from, to, sel, actloop)
    depth = depth or 0
    local build = ("  "):rep(depth)..(loop.label == "^" and "(*)" or (loop.label ~= "" and "("..loop.label.."*)" or "*"))..loop.amount:gsub("i", "∞").."<"..(#loop.commands > 0 and "\n" or "")
    for _,v in ipairs(loop.commands) do
        if v.type then
            build = build..("  "):rep(depth + 1)..v.type..(v.param or "").."\n"
        else
            build = build..progdump(v, depth + 1).."\n"
        end
    end
    build = build..("  "):rep(#loop.commands > 0 and depth or 0)..">"
    if not from or not to then return build end
    local finalout = ""
    local _, lines = build:gsub("\n", "\n")
    lines = lines + 1
    if from < 1 then to = to - from + 1; from = 1 end
    if to > lines then from = from - (to - lines); to = lines end
    local i = 1
    local maxwidth = 0
    for line in build:gmatch("[^\n]+") do
        if i >= from and i <= to then
            finalout = finalout..(sel and (i == sel and "> " or "  ") or "")..indent(i, to).." │ "..line.."\n"
            maxwidth = math.max(maxwidth, #line)
        end
        i = i + 1
    end
    finalout = finalout..("─"):rep(3 + #tostring(to)).."┴"..("─"):rep(maxwidth + 2).."\nIndexes:\n"
    local indcur = actloop
    local indthrough = {}
    local indmax = ""
    while indcur.parent do
        table.insert(indthrough, 1, indcur)
        if #indcur.label > #indmax then indmax = indcur.label end
        indcur = indcur.parent
    end
    for _,v in ipairs(indthrough) do
        if v.label == "^" then
            finalout = finalout..indent("(*)", "("..indmax.."*)").." = "..v.n.." of "..v.max.."\n"
        elseif v.label ~= "" then
            finalout = finalout..indent("("..v.label.."*)", "("..indmax.."*)").." = "..v.n.." of "..v.max.."\n"
        else
            finalout = finalout..indent("* ", "("..indmax.."*)").." = "..v.n.." of "..v.max.."\n"
        end
    end
    local visitout = {}
    for i,v in pairs(labels) do
        if i ~= "^" and i ~= "" then
            table.insert(visitout, {i = i, t = indent("("..i.."*)", "("..highestlabel.."*)").." = "..v})
        end
    end
    table.sort(visitout, function(a, b) return a.i < b.i end)
    if #visitout > 0 then
        finalout = finalout..("─"):rep(6 + #tostring(to) + maxwidth).."\nVisits:\n"..indent("(*)", "("..highestlabel.."*)").." = "..labels["^"]
        for _,v in ipairs(visitout) do finalout = finalout.."\n"..v.t end
    end
    finalout = finalout.."\n"..("─"):rep(6 + #tostring(to) + maxwidth).."\n"..out
    return "\x1B[2J\x1B[H"..finalout
end

function run(loop)
    loop.n = 0
    labels[loop.label] = (labels[loop.label] or 0) + 1
    local amount = loopamount(loop)
    loop.max = amount
    if flags.debug then
        print(progdump(loops[1], 0, loop.parseline - flags.linesup, loop.parseline + flags.linesdown, loop.parseline, loop))
        if not flags.autocycle then io.read()
        elseif tonumber(flags.autocycle) then os.execute("sleep "..flags.autocycle) end -- pause
    end
    while loop.n < amount do
        loop.n = loop.n + 1
        for _,v in ipairs(loop.commands) do
            if v.type then
                local retvalue = nil
                local doreturn = false
                local dobreak = false
                if v.type == "!" and not v.param then
                    loop.n = 0
                    doreturn = true
                elseif v.type == "!" and v.param then
                    local get = rcsearch(loop, v.param)
                    if get then
                        loop.n = 0
                        retvalue = function(l) return l ~= get.parent end
                        doreturn = true
                    end
                elseif v.type == "&" and (not v.param or v.param == loop.label) then
                    dobreak = true
                elseif v.type == "&" and v.param then
                    local get = rcsearch(loop, v.param)
                    if get then
                        loop.n = 0
                        retvalue = function(l) return l == get and "break" or true end
                        doreturn = true
                    end
                elseif v.type == "@" then
                    if flags.debug then out = out..tostring(loop.n)
                    else io.write(tostring(loop.n)) end
                elseif v.type == "~@" then
                    if flags.debug then out = out..toutf8(loop.n)
                    else io.write(toutf8(loop.n)) end
                elseif v.type == "$" then
                    labels[v.param] = 0
                end
                if flags.debug then
                    print(progdump(loops[1], 0, v.parseline - flags.linesup, v.parseline + flags.linesdown, v.parseline, loop))
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
    print(progdump(current))
end
if flags.parserdump then
    print(dump(current))
end
run(current)
