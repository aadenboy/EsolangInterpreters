Public repository of the interpreters I've implemented for [my esolangs](https://esolangs.com/wiki/User:Aadenboy). This does not include [Kawa](https://github.com/aadenboy/Kawa-IDE) nor [Smolder](https://github.com/aadenboy/smolder), which are their own experiences implemented in [LÖVE](https://love2d.org/).

## Trampolines
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;*TODO: Remake the interpreter, it's been two years.*

Use `Trampolines.lua` for a dedicated CLI experience, with a visual debugger. The program will ask for a file when it runs. Arguments are hard-baked in.

Use `TrampolinesNoSTDIO.lua` for embedding. A visual debugger is not included. Pass the file and any additional arguments in order when running.

```lua
--[[
useANSI = true    -- boolean | write "\x1B[2J\x1B[H" to console? (clears console)
prompt  = true    -- boolean | ask "AWAITING ASCII INPUT: " and or "AWAITING NUMBER INPUT: " when getting input?
pcustom = true    -- boolean | ask a custom prompt when getting input?
pnum    = false   -- boolean | print what's inputted after a default prompt?
pcnum   = false   -- boolean | print what's inputted after a custom prompt?
]]
```

## Iterate
`Iterate.lua` provides a dedicated CLI experience and supports embedding, alongside a visual debugger. The file is passed as the first non-flag argument. Optionally, an input file may be included. If none is provided, one will be emulated via prompting the user. If there is no file, add the `--emptyinput` flag. Additional flags may be added in any order.

```lua
local flags = {
    dump = false,             -- dump the parsed program expanded to the console
    parserdump = false,       -- dump the parsed program as a lua table to the console
    emptyinput = false,       -- mark the input as empty to prevent CLI io
    debug = false,            -- run the program in debug mode (requires an input file or --emptyinput flag set)
    autocycle = false,        -- automatically cycle through the program in debug mode
    autocycledelay = -1,      -- delay between cycles in debug mode in seconds (sets --autocycle to true)
    linesup = 5,              -- number of lines to show above the current line in debug mode
    linesdown = 5,            -- number of lines to show below the current line in debug mode
    stickyloops = false,      -- show the lines of the parent loops in debug mode, even if they are out of view
    hideunlabeled = false,    -- hide the indexes of unlabeled loops in debug mode
    maxindexes = math.huge,   -- maximum number of indexes to show in debug mode
    hideunvisited = false,    -- hide the visits of unvisited loops in debug mode
    inputbytes = 10,          -- number of bytes to read from the input at a time in debug mode
    inputbytetype = "number", -- type of input bytes to show in debug mode (number, bits, hex, utf8)
    maxoutbytes = math.huge,  -- maximum number of bytes to show in the output in debug mode
}
```
