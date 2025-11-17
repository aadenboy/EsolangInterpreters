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
    hideunvisited = false, -- hide the visits of unvisited loops in debug mode
    inputbytes = 10,      -- number of bytes to read from the input at a time in debug mode
    inputbytetype = "number", -- type of input bytes to show in debug mode (number, bits, hex, utf8)
    maxoutbytes = math.huge,     -- maximum number of bytes to show in the output in debug mode
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
           :gsub("[^()<>*0-9~ni=?%^!@&%%%$\n]", "") -- \n to preserve line numbers

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
    elseif s:match("^[~%%]?@") then
        local kind = s:match("^[~%%]?@")
        local command = {
            type = kind,
            line = line,
            parseline = parseline
        }
        table.insert(current.commands, command)
        i = i + #kind
        parseline = parseline + 1
    elseif s:match("^%$[0-9%^]?") then
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

function ioprompt()
    if not usefile and inputbit > #input then input = io.read().."\0"; inputbit = 1 end
end
function contstonum(pre, len)
    local out = pre % 2^(8-len)
    inputbit = inputbit + len - 1
    for i=1, len do
        local v = input:byte(inputbit + i - 1)
        if math.floor(v / 0x40) ~= 0x2 then return 0 end
        out = out * 0x100 + v % 0x40
    end
    return out
end
function loopamount(loop, first)
    if first == nil then first = true end
    local la = loop.amount
    if la:match("^%d+$") then
        return tonumber(la)
    elseif la == "i" then
        return math.huge
    elseif la == "?" then
        if first == true then
            ioprompt()
            local num, past = input:sub(inputbit):match("(%d+)()")
            inputbit = past or #input + 1
            while not usefile and not num do
                ioprompt()
                num, past = input:sub(inputbit):match("(%d+)()")
                inputbit = past or #input + 1
            end
            loop.cache = tonumber(num) or 0
        end
        return loop.cache
    elseif la == "~?" then
        if first == true then
            ioprompt()
            local char = input:byte(inputbit)
            inputbit = inputbit + 1
            loop.cache = 0
            if not char then -- shrug
            elseif math.floor(char / 0x40) == 0x2 then -- invalid utf-8
            elseif char < 0x80 then
                loop.cache = char
            elseif char < 0xE0 then
                loop.cache = contstonum(char, 2)
            elseif char < 0xF0 then
                loop.cache = contstonum(char, 3)
            elseif char < 0xF8 then
                loop.cache = contstonum(char, 4)
            end
        end
        return loop.cache
    elseif la == "%?" then
        if first == true then
            ioprompt()
            loop.cache = input:byte(inputbit) or 0
            inputbit = inputbit + 1
        end
        return loop.cache
    elseif la == "n" then
        return loop.parent.n or 0
    elseif la:match("^n%d+$") or la == "n^" then
        for _,v in ipairs(loops) do if v.label == la:sub(2) then return v.n end end
    elseif la == "~n" then
        return loopamount(loop.parent, false) - (loop.parent.n or 0)
    elseif la:match("^~n%d+$") or la == "~n^" then
        for _,v in ipairs(loops) do if v.label == la:sub(3) then return loopamount(v, false) - v.n end end
    elseif la == "=" then
        return loop.parent.visits or 0
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

    local ancestors = {actloop}
    local sticky = {}
    local indmax = ""
    while true do
        local cur = ancestors[1]
        sticky[cur.parseline] = true
        if #cur.label > #indmax then indmax = cur.label end
        if cur.parent.parent then table.insert(ancestors, 1, cur.parent) else break end
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
        if i > #ancestors-flags.maxindexes then
            if v.label == "^" then
                finalout = finalout..indent("(*)", "("..indmax.."*)").." = "..v.n.." of "..v.max.."\n"
            elseif v.label ~= "" then
                finalout = finalout..indent("("..v.label.."*)", "("..indmax.."*)").." = "..v.n.." of "..v.max.."\n"
            elseif not flags.hideunlabeled then
                finalout = finalout..indent("* ", "("..indmax.."*)").." = "..v.n.." of "..v.max.."\n"
            end
        end
    end

    local visitout = {}
    for i,v in pairs(labels) do
        if i ~= "^" and i ~= "" and (not flags.hideunvisited or v > 0) then
            table.insert(visitout, {i = i, t = indent("("..i.."*)", "("..highestlabel.."*)").." = "..v})
        end
    end
    table.sort(visitout, function(a, b) return a.i+0 < b.i+0 end)
    if #visitout > 0 then
        finalout = finalout..("─"):rep(6 + #tostring(to) + maxwidth).."\nVisits:\n"..indent("(*)", "("..highestlabel.."*)").." = "..labels["^"]
        for _,v in ipairs(visitout) do finalout = finalout.."\n"..v.t end
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

function run(loop)
    loop.n = 0
    loop.visits = loop.visits + 1
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
                elseif v.type == "%@" then
                    if flags.debug then out = out..string.char(loop.n % 256)
                    else io.write(string.char(loop.n % 256)) end
                elseif v.type == "$" and not v.param then
                    loop.parent.visits = 0
                elseif v.type == "$" and v.param then
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
