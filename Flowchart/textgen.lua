local base = {
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
}
local s = io.read()

for i=1, #s do
    local n = s:byte(i)
    for i=1, 8 do
        base[i] = base[i].."─"..(n % 2 == 1 and "[ }" or "{ ]").."─\\ \\"
        n = math.floor(n / 2)
    end
end
print("Parallel (multiple pointers): \n"..table.concat(base, "\n"))

local base = {}
for i=1, #s do
    local n = s:byte(i)
    table.insert(base, "")
    for j=1, 8 do
        if i%2==1 then base[i] = base[i].."─"..(n % 2 == 1 and "[ }" or "{ ]").."─\\ \\"
                  else base[i] = "\\ \\─"..(n % 2 == 1 and "[ }" or "{ ]").."─"..base[i] end
        n = math.floor(n / 2)
    end
end
print("Weave (single pointer): \n"..table.concat(base, "\n"))