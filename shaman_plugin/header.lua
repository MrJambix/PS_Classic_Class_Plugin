local plugin = {}

plugin["name"] = "Shaman_Plugin"
plugin["version"] = "0.1.0"
plugin["author"] = "MrJambix"
plugin["load"] = true

local core = _G.core
if not core then
    plugin["load"] = false
    return plugin
end

-- check if local player exists before loading the script (user is on loading screen / not ingame)
local local_player = core.object_manager.get_local_player()
if not local_player then
    plugin["load"] = false
    return plugin
end

---@type enums
local enums = require("common/enums")
local player_class = local_player:get_class()

-- change this line with the class of your script
local is_valid_class = player_class == enums.class_id.SHAMAN

if not is_valid_class then
    plugin["load"] = false
    return plugin
end

plugin["description"] = "Shaman rotation plugin for core"
return plugin