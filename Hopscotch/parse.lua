assert(arg[1] and arg[2] and arg[3], "Usage: lua parse.lua <hopscotch project> <object ID> <output file>")

local types = require("types")
local format = require("format")

local pname = arg[1]
local pfile = io.open(pname, "r")
assert(pfile, "File not found")
local pstring = pfile:read("*a")
pfile:close()
local project = require("json").decode(pstring)

function findById(space, attr, id)
    for i,v in ipairs(space) do
        if v[attr] == id then
            return v
        end
    end
end

local objectid = arg[2]
local object = findById(project.objects, "objectID", objectid)
assert(object, "Object "..objectid.." not found")

function renderBlock(block, instance, nesting, localnesting)
    if block.filename then -- object
        local wikitext = "{{H|container|object"
                       .."\n|{{H|label|"..(block.name or "Object").."}}"
                       .."{{H|operator|object|1|"
                       ..(block.type == 1 and "{{H|label|Text}}{{H|value|"..block.text.."}}" or "{{H|label|sprite}}{{H|value|"..block.type.."}}")
                       .."}}"
                       .."\n|"
        local ability = findById(project.abilities, "abilityID", block.abilityID)
        if ability then wikitext = wikitext..renderBlock(ability) end
        for i,v in ipairs(block.rules) do
            local rule = findById(project.rules, "id", v)
            assert(rule, "Rule "..v.." not found")
            wikitext = wikitext..renderBlock(rule)
        end
        return wikitext.."|{{H|label|End}}\n|}}\n"
    elseif block.blocks then -- ability
        local wikitext = ""
        for i,v in ipairs(block.blocks) do wikitext = wikitext..renderBlock(v) end
        return wikitext
    elseif block.ruleBlockType then -- rule
        assert(block.parameters[1], "Rule "..block.id.." has no parameters")
        local wikitext = "{{H|container|rule"
                       .."\n|{{H|label|When}}"
                       ..renderBlock(block.parameters[1], "rule", 0, 1)
                       .."\n|"
        local ability = findById(project.abilities, "abilityID", block.abilityID)
        assert(ability, "Ability "..block.abilityID.." not found")
        wikitext = wikitext..renderBlock(ability)
        return wikitext.."|{{H|label|End}}\n|}}\n"
    elseif block.controlScript then -- control
        local template = format[block.type]
        assert(template, "No template for type "..block.type.." found")
        local color = types[block.type] or "unknown"
        template = template:gsub("{{{(%d+)}}}", function(i) i=i+0
            assert(block.parameters[i], "Block "..block.description.." has no argument "..i)
            return renderBlock(block.parameters[i], color, 0, 1)
        end):gsub("{{{(%w+)}}}", function(i)
            assert(block[i], "Block "..block.description.." has no field "..i)
            local ability = findById(project.abilities, "abilityID", block[i].abilityID)
            assert(ability, "Ability "..block[i].abilityID.." not found")
            return renderBlock(ability)
        end)
        return template.."\n"
    elseif block.block_class == "method" then -- block
        local template = format[block.type]
        assert(template, "No template for type "..block.type.." found")
        local color = types[block.type] or "unknown"
        template = template:gsub("{{{(%d+)}}}", function(i) i=i+0
            assert(block.parameters[i], "Block "..block.description.." has no argument "..i)
            return renderBlock(block.parameters[i], color, 0, 1)
        end)
        return template.."\n"
    elseif block.datum and not block.datum.variable then -- operator
        block.datum.type = block.datum.type or block.datum.HSTraitTypeKey
        local template = format[block.datum.type]
        assert(template, "No template for type "..block.datum.type.." found")
        local color = types[block.datum.type] or "unknown"
        if color ~= "property" and color ~= "math" and color ~= "text" then color = "unknown" end
        if color == "text" then localnesting = 0 end
        template = template:gsub("{{{(%d+)}}}", function(i) i=i+0
            assert(block.datum.params[i], "Operator "..(block.description or block.type).." has no argument "..i)
            return renderBlock(block.datum.params[i], color, nesting+1, localnesting+1)
        end)
        if color == "unknown" then template = template:gsub("^(.-|operator|)[^|]+", "%1"..instance) end
        if color == "math" and nesting > 0 then template = template:gsub("^(.-|operator|[^|]+|)", "%1"..math.min(nesting, 5).."|")
        elseif color ~= "property" and color ~= "text" and color ~= "math" and localnesting > 0 then template = template:gsub("^(.-|operator|[^|]+|)", "%1"..math.min(localnesting, 5).."|") end
        return template
    elseif block.datum and block.datum.variable then -- variable
        local template = format[block.datum.type]
        assert(template, "No template for type "..block.datum.type.." found")
        local variable = findById(project.variables, "objectIdString", block.datum.variable)
        assert(template, "Variable "..block.datum.variable.." not found")
        template = template:gsub("{{{1}}}", variable.name)
        return template
    else -- value
        return "{{H|value|"..((block.value or ""):match("\n") and "2=" or "")..(block.value or ""):gsub("\n", '<span style="color:#0006">\\n</span>').."}}"
    end
end

local outfile = io.open(arg[3], "w")
outfile:write((renderBlock(object):gsub("{{H", "{{:Hopscotch (Hopscotch Technologies)")))
outfile:close()