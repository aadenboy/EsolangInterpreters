local utf8 = require("utf8")

local prog = arg[1]
local file = io.open(prog, "r")
local code = file:read("*a")
file:close()

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
           :gsub("[^()<>*0-9~ni=?%^!@&%$]", "")

local loops = {}
local current = {}
local i = 1
function rcassert(from, tag)
    if tag == "" then return true end
    if from.labels[tag] then return false end
    if from == loops[1] then return true end
    return rcassert(from.parent, tag)
end
function rcsearch(from, tag)
    if tag == "" then return end
    if from.label == tag then return from end
    if from == loops[1] then return from end
    return rcsearch(from.parent, tag)
end
repeat
    local s = code:sub(i)

    if s:match("^%(%*%).-%b<>") and #loops == 0 then
        loops[1] = {
            label = "^",
            amount = s:match("^%(%*%)(.-)%b<>"),
            commands = {},
            parent = {},
            n = 0, visits = 0,
            labels = {}
        }
        current = loops[1]
        i = i + s:match("^%(%*%).-()%b<>")
    elseif s:match("^%(%d+%*%).-%b<>") then
        local loop = {
            label = s:match("^%((%d+)"),
            amount = s:match("^%(%d+%*%)(.-)%b<>"),
            commands = {},
            parent = current,
            n = 0, visits = 0,
            labels = {}
        }
        assert(rcassert(loop.parent, loop.label), "Duplicate labels in the same scope are not allowed (label "..loop.label..")")
        for i,v in ipairs(loop.parent.labels or {}) do
            loop.labels[i] = v
        end
        loop.labels[loop.label] = true
        loop.parent.labels[loop.label] = true
        table.insert(loops, loop)
        table.insert(current.commands, loop)
        current = loop
        i = i + s:match("^%(%d+%*%).-()%b<>")
    elseif s:match("^%*.-%b<>") then
        local loop = {
            label = "",
            amount = s:match("^%*(.-)%b<>"),
            commands = {},
            parent = current,
            n = 0, visits = 0,
            labels = {}
        }
        table.insert(loops, loop)
        table.insert(current.commands, loop)
        current = loop
        i = i + s:match("^%*.-()%b<>")
    elseif s:match("^[!&]") then
        local kind = s:match('^(.)')
        local command = {
            type = kind,
            param = s:match("^"..kind.."(%d+)") or s:match("^"..kind.."(%^)")
        }
        table.insert(current.commands, command)
        i = i + 1 + #(command.param or "")
    elseif s:match("^[@~]") then
        local kind = s:match("^~") and "~@" or "@"
        local command = {
            type = kind
        }
        table.insert(current.commands, command)
        i = i + #kind
    elseif s:match("^%$[0-9%^]") then
        local kind = s:match('^(.)')
        local command = {
            type = "$",
            param = s:match("^%$(%d+)") or s:match("^%$(%^)")
        }
        table.insert(current.commands, command)
        i = i + 1 + #command.param
    elseif s:match("^>") then
        current = current.parent
        i = i + 1
    else
        i = i + 1
    end
until i >= #code

current = loops[1]
if not current or current.label ~= "^" then return end

local labels = {}
function loopamount(loop, first)
    if first == nil then first = true end
    local la = loop.amount
    if la:match("^%d+$") then
        return tonumber(la)
    elseif la == "i" then
        return math.huge
    elseif la == "?" then
        if first == true then loop.cache = io.read() end
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

function run(loop)
    loop.n = 0
    labels[loop.label] = (labels[loop.label] or 0) + 1
    local amount = loopamount(loop)
    while loop.n < amount do
        loop.n = loop.n + 1
        for _,v in ipairs(loop.commands) do
            if v.type then
                if v.type == "!" and not v.param then
                    loop.n = 0
                    return
                elseif v.type == "!" and v.param then
                    local get = rcsearch(loop, v.param)
                    if get then
                        loop.n = 0
                        return function(l) return l ~= get.parent end
                    end
                elseif v.type == "&" and (not v.param or v.param == loop.label) then
                    break
                elseif v.type == "&" and v.param then
                    local get = rcsearch(loop, v.param)
                    if get then
                        loop.n = 0
                        return function(l) return l == get and "break" or true end
                    end
                elseif v.type == "@" then
                    io.write(tostring(loop.n))
                elseif v.type == "~@" then
                    io.write(utf8.char(loop.n))
                elseif v.type == "$" then
                    labels[v.param] = 0
                end
            else
                local outer = run(v) or function() return false end
                if outer(loop) == true then return outer end
                if outer(loop) == "break" then break end
            end
        end
    end
end
run(current)