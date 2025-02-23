-- aaden
-- physics based esolang :P

-- ARGS:
file    = arg[1]                            -- directory | the file to open
useANSI = arg[2] == nil and true or arg[2]  -- boolean   | write "\x1B[2J\x1B[H" to console? (clears console, here just incase you will extract output)
prompt  = arg[3] == nil and true or arg[3]  -- boolean   | ask "AWAITING ASCII INPUT: " and or "AWAITING NUMBER INPUT: " when getting input?
pcustom = arg[4] == nil and true or arg[4]  -- boolean   | ask a custom prompt when getting input?
pnum    = arg[5] == nil and false or arg[5] -- boolean   | print what's inputted after a default prompt, e.g if a 19 was inputted, should it print 19 and then a newline?
pcnum   = arg[6] == nil and false or arg[6] -- boolean   | print what's inputted after a custom prompt?

math.randomseed(os.time())

local debug

local output = ""

function write(...)
    io.write(...)
    for _,v in ipairs({...}) do
        output = output..v
    end
end

local f = io.open(file, "r"):read("*all")

local running = string.sub(file, -5, -1) == "tramp" or string.sub(file, -3, -1) == "txt"

local olderror = error
function error(s, cond)
    cond = cond == nil and true or cond

    if cond then
        io.stderr:write(tostring(s)) -- stderr moment
        os.exit(1)
    end
end

function string.split(inputstr, sep, strict)
    sep = sep or "%s"
    strict = strict == false and "*" or "+"

    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]"..strict..")") do
        table.insert(t, str)
    end
    return t
end

function math.sign(n, zerosign)
    return n < 0 and -1 or (n > 0 and 1 or (zerosign or 1))
end

function math.round(n)
    return n - math.floor(n) >= 0.5 and math.ceil(n) or math.floor(n)
end

local field = io.open(file):read("*a")

error("The inputted file must be a valid .tramp or .txt file. You gave an invalid file.", not running)

local lines = string.split(field, "\r\n")
local width = string.len(lines[1])
local height = #lines

for i,v in ipairs(lines) do
    error("The width of the playing field is inconsistent. First inconsistency found at: "..i..".", string.len(v) ~= width)
    error("Line "..i.." is missing the \"|\" character at the start.", string.sub(lines[i], 1, 1) ~= "|")
    error("Line "..i.." is missing the \"#\" character at the end.", string.sub(lines[i], -1, -1) ~= "#")
end

local pos = {
    x = 0,
    y = 0
}

local foundspawn = false

for i,v in pairs(lines) do
    if string.find(v, "o") ~= nil then
        local instr = false
        for j=1, #v do
            if string.sub(v, j, j) == "\"" then instr = not instr end
            if string.sub(v, j, j) == "o" and not instr then pos.x = j - 1 pos.y = i - 1 foundspawn = true break end
        end
    end
   
    if foundspawn then break end
end

error("No marble spawnpoint has been found. You need to create one using the \"o\" command.", not foundspawn)

local vel = {
    x = 0,
    y = 0
}
-- local a = "\\"

-- local objects = "H|#"..string.char(92)..".=-"

local strings = {}

for i,v in ipairs(lines) do
    strings[i] = {}
    local len = 0

    error("Line "..i.."has an incomplete string.", #string.split(v, "\"", false) % 2 == 0)

    for o,b in ipairs(string.split(v, "\"", false)) do
        if o % 2 == 0 then
            strings[i][#strings[i]+1] = {x = len + 1, content = b}
        end
        len = len + #b
    end
end

local stack = {{}, {}, {}}
local stackpointer = 1

local function showstack()
    local s = ""
    for i,v in ipairs(stack) do
        if stackpointer == i then
            s = s.."> "
        end
        s = s.."Stack "..i..": "
        for _,t in ipairs(v) do
            t2 = math.round(t)

            if t2 > 31 and t2 < 1112064 then
                s = s..t.." ("..utf8.char(t2)..")\t"
            else
                local list = {"NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", "TAB", "LF", "VT", "DD", "CR", "SO", "SI", "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB", "CAN", "EM", "SUB", "ESC", "FS", "GS", "RS", "US"}
                s = s..t.." ("..(list[t2+1] or "???")..")\t"
            end
        end
        s = s.."\n"
    end
    return string.sub(s, 1, -2)
end

function push(stacknum, num)
    stack[stacknum][#stack[stacknum]+1] = num
end

function pop(stacknum, degree)
    error("Attempted to pop from stack "..stacknum..", which is an empty stack. Position: ("..pos.x..", "..pos.y..")", #stack[stacknum] == 0)

    if degree == nil then
        degree = 1
    end
    for _=1, degree do
        stack[stacknum][#stack[stacknum]] = nil
    end
end

function retrieve(stacknum, place)
    place = place == nil and #stack[stacknum] or #stack[stacknum] - (place - 1)
    error("Attempted to get value "..place.." from stack "..stacknum..", which has a length of "..#stack[stacknum]..". Position: ("..pos.x..", "..pos.y..")\n"..showstack(), stack[stacknum][place] == nil)

    return stack[stacknum][place]
end

if useANSI then
    io.write("\x1B[2J\x1B[H")
end

output = ""

local collisions = {
    ["35"] = function() -- #
        os.exit()
    end,
    ["124"] = function() -- -
        vel.x = vel.x * -1
    end,
    ["45"] = function() -- |
        vel.y = vel.y * -1
    end,
    ["72"] = function() -- H
        vel.x = 0
        vel.y = math.sign(vel.y)
    end,
    ["61"] = function() -- =
        vel.y = 0
        vel.x = math.sign(vel.x)
    end,
    ["92"] = function() -- \
        if math.sign(vel.y, -1) == 1 then
            vel.x = 1
            vel.y = -1
        else
            vel.x = -1
            vel.y = 1
        end
    end,
    ["47"] = function() -- /
        if math.sign(vel.y, -1) == 1 then
            vel.x = -1
            vel.y = -1
        else
            vel.x = 1
            vel.y = 1
        end
    end,
    ["46"] = function() -- .
        if #strings[pos.y + 1] == 0 then
            write("\n")
            return
        end

        for _,v in ipairs(strings[pos.y + 1]) do
            if v.x == pos.x + 2 then
                write(v.content)
                return
            end
        end
    end,
    ["48"] = function() -- 0 - 9
        push(stackpointer, tonumber(string.sub(lines[pos.y + 1], pos.x + 1, pos.x + 1)))
    end,
    ["63"] = function() -- ?
        push(stackpointer, math.random(0, 1000) / 1000)
    end,
    ["40"] = function() -- (
        local num = math.floor(retrieve(stackpointer))
        pop(stackpointer)
        push(stackpointer, num)
    end,
    ["41"] = function() -- )
        local num = math.ceil(retrieve(stackpointer))
        pop(stackpointer)
        push(stackpointer, num)
    end,
    ["36"] = function() -- $
        local num = math.round(retrieve(stackpointer))
        pop(stackpointer)
        push(stackpointer, num)
    end,
    ["94"] = function() -- ^
        pop(stackpointer)
    end,
    ["126"] = function() -- ~
        push(stackpointer, retrieve(stackpointer))
    end,
    ["42"] = function() -- *
        local num = retrieve(stackpointer, 2) * retrieve(stackpointer)
        pop(stackpointer, 2)
        push(stackpointer, num)
    end,
    ["37"] = function() -- %
        local num = retrieve(stackpointer, 2) % retrieve(stackpointer)
        pop(stackpointer, 2)
        push(stackpointer, num)
    end,
    ["43"] = function() -- +
        local num = retrieve(stackpointer, 2) + retrieve(stackpointer)
        pop(stackpointer, 2)
        push(stackpointer, num)
    end,
    ["58"] = function() -- :
        write(utf8.char(math.round(retrieve(stackpointer))))
        pop(stackpointer)
    end,
    ["59"] = function() -- ;
        write(tostring(retrieve(stackpointer)))
        pop(stackpointer)
    end,
    ["33"] = function() -- !
        local num = retrieve(stackpointer) * -1
        pop(stackpointer)
        push(stackpointer, num)
    end,
    ["39"] = function() -- '
        local num = 1/(retrieve(stackpointer))
        pop(stackpointer)
        push(stackpointer, num)
    end,
    ["44"] = function() -- ,
        local custom = false

        if #strings[pos.y + 1] ~= 0 and pcustom then
            for _,v in ipairs(strings[pos.y + 1]) do
                if v.x == pos.x + 2 then
                    write(v.content)
                    custom = v.content
                    break
                end
            end

            if not custom then
                write(({"\nAWAITING NUMBER INPUT: ", "\nAWAITING CHAR INPUT: ", "AWAITING INPUT: "})[stackpointer])
            end
        else
            if prompt then
                write(({"\nAWAITING NUMBER INPUT: ", "\nAWAITING CHAR INPUT: ", "AWAITING INPUT: "})[stackpointer])
            end
        end

        local input

        if stackpointer == 1 then
            repeat
                input = io.read("*n")
            until tonumber(input) ~= nil

            push(stackpointer, input)
        elseif stackpointer == 2 then
            repeat
                input = io.read()
            until input ~= nil

            push(stackpointer, utf8.codepoint(input:sub(1, 1)))
        else
            repeat
                input = io.read()
            until input ~= nil
           
            for c in string.gmatch(input:reverse(), "(.)") do
                push(stackpointer, utf8.codepoint(c))
            end
        end

        if (pnum and not custom) or (pcnum and custom) then
            write(input.."\n")
        else
            output = output..input.."\n"
        end
    end,
    ["60"] = function() -- <
        if retrieve(stackpointer, 2) >= retrieve(stackpointer) then
            vel.y = vel.y * -1
        end
    end,
    ["62"] = function() -- >
        if retrieve(stackpointer, 2) <= retrieve(stackpointer) then
            vel.y = vel.y * -1
        end
    end,
    ["95"] = function() -- _
        local a = retrieve(stackpointer)
        pop(stackpointer)
        local b = retrieve(stackpointer)
        pop(stackpointer)
        push(stackpointer, a)
        push(stackpointer, b)
    end,
    ["64"] = function() -- @
        local num = tonumber(tostring(retrieve(stackpointer, 2))..tostring(retrieve(stackpointer)))
        pop(stackpointer)
        pop(stackpointer)
        push(stackpointer, num)
    end,
    ["38"] = function() -- &
        local split = retrieve(stackpointer)
        local original = retrieve(stackpointer, 2)
        pop(stackpointer)
        pop(stackpointer)
        push(stackpointer, tonumber(string.split(tostring(original), 1, split)))
        push(stackpointer, tonumber(string.split(tostring(original), split + 1, -1)))
    end,
    ["91"] = function() -- [
        push(((stackpointer - 2) % 3) + 1, retrieve(stackpointer))
        pop(stackpointer)
    end,
    ["93"] = function() -- ]
        push(math.max((stackpointer + 1) % 4, 1), retrieve(stackpointer))
        pop(stackpointer)
    end,
    ["123"] = function() -- {
        stackpointer = ((stackpointer - 2) % 3) + 1
    end,
    ["125"] = function() -- }
        stackpointer = math.max((stackpointer + 1) % 4, 1)
    end,
}

for i=49, 57 do
    collisions[tostring(i)] = collisions["48"]
end

while running do

    error("The marble fell to the bottom... Position: ("..pos.x..", "..pos.y..")", pos.y == height)
    error("The marble went too high... Position: ("..pos.x..", "..pos.y..")", pos.y == -1)

    local funct = "0"
    for i,v in pairs(collisions) do
        if tonumber(i) == string.byte(string.sub(lines[pos.y + 1], pos.x + 1, pos.x + 1)) then
            local instring = false
            local incomment = false

            for a=1, pos.x + 1 do
                if string.sub(lines[pos.y + 1], a, a) == "\"" and not incomment then
                    instring = not instring
                elseif string.sub(lines[pos.y + 1], a, a) == "`" and not instring and not incomment then
                    incomment = not true
                end
                if string.sub(lines[pos.y + 1], a, a) == string.sub(lines[pos.y + 1], pos.x + 1, pos.x + 1) then
                    break
                end
            end
            if not incomment and not instring then
                funct = i
                break
            end
        end
    end
    if funct ~= "0" then
        collisions[funct]()
    end

    if debug then
        local split = #string.split(output, "\n", false) == 0 and {""} or string.split(output, "\n", false)
        local shown = ""

        for i,v in pairs(lines) do

            if i >= pos.y + 1 - (dispheight / 2) and i <= pos.y + 1 + (dispheight / 2) then
                if i == pos.y + 1 then
                    shown = shown..string.sub(v, math.ceil(math.max(pos.x + 1 - (dispwidth / 2), 0)), pos.x).."Q"..string.sub(v, pos.x + 2, math.ceil(math.max(pos.x + 1 + (dispwidth / 2), 0))).."\n"
                else
                    shown = shown..string.sub(v, math.ceil(math.max(pos.x + 1 - (dispwidth / 2), 0)), math.ceil(math.max(pos.x + 1 + (dispwidth / 2), 0))).."\n"
                end
            end
        end

        print("\x1b[2J"..output.."\x1b[0m\n^^^ Output ^^^\nvvv Playing Field vvv\n"..shown.."\n"..showstack().."\nBall Position: {"..pos.x..", "..pos.y.."}\nBall Velocity: {"..vel.x..", "..vel.y.."}\nHit enter to advance")
        io.read()
    end

    pos.x = pos.x + math.sign(vel.x, 0)
    pos.y = pos.y + math.sign(vel.y, 0)
    vel.y = math.min(vel.y + 0.5, 1)
end