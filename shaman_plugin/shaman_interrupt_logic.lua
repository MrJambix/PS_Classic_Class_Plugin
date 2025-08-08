local unit_helper = require("common/utility/unit_helper")
local spell_helper = require("common/utility/spell_helper")
local spell_queue = require("common/modules/spell_queue")
local wigs_tracker = require("common/utility/wigs_tracker")
local profiler = require("common/modules/profiler")
local core = _G.core
local shaman_data = require("shaman_spells_buffs")
local SPELLS = shaman_data.SPELLS

local HEAL_SPELLS = {
    "Heal","Lesser Heal","Flash Heal","Greater Heal","Holy Light","Prayer of Healing","Healing Wave","Chain Heal","Dark Mending"
}
local CC_SPELLS = {
    "Polymorph","Hex","Sleep","Dominate Mind","Mind Control","Possess","Seduction"
}
local FEAR_SPELLS = {
    "Psychic Scream","Howl of Terror","Intimidating Shout","Terrify","Terror","Banshee Wail"
}
local AOE_NUKES = {
    "Shadow Bolt Volley","Fireball Volley","Frostbolt Volley","Chain Lightning","Arcane Missiles","Flamestrike","Blizzard","Rain of Fire","Hellfire","Mind Flay"
}
local UTILITY_SPELLS = {
    "Resurrection","Revive","Ancestral Spirit","Summon Skeleton","Summon Voidwalker","Summon","Veil of Shadow"
}

local function contains_spell(spell_name, list)
    local s = spell_name:lower()
    for _, v in ipairs(list) do
        if s:find(v:lower()) then return true end
    end
    return false
end

local function get_highest_earth_shock()
    for i = #SPELLS.EarthShock, 1, -1 do
        if spell_helper:has_spell_equipped(SPELLS.EarthShock[i]) then
            return SPELLS.EarthShock[i]
        end
    end
    return nil
end

local function interrupt_logic()
    if not auto_interrupt.value then return end
    local player = core.object_manager.get_local_player()
    if not player then return end

    local enemies = unit_helper:get_enemy_list_around(player:get_position(), 30, true, false, false, false)
    local interrupt_target, interrupt_priority = nil, nil
    local interrupt_spell_name = nil

    -- Scan for casting enemies
    for _, unit in ipairs(enemies) do
        if unit_helper:is_valid_enemy(unit) and not unit:is_dead() and not unit_helper:is_dummy(unit) then
            local cast_info = unit.get_cast_info and unit:get_cast_info()
            if cast_info and cast_info.is_casting and not cast_info.is_uninterruptible then
                local spell_name = cast_info.spell_name or ""
                -- Prioritize CC
                if contains_spell(spell_name, CC_SPELLS) then
                    interrupt_target, interrupt_priority, interrupt_spell_name = unit, 1, spell_name
                    break
                -- Heals (always kick)
                elseif contains_spell(spell_name, HEAL_SPELLS) then
                    interrupt_target, interrupt_priority, interrupt_spell_name = unit, 2, spell_name
                    break
                -- Fears
                elseif contains_spell(spell_name, FEAR_SPELLS) then
                    interrupt_target, interrupt_priority, interrupt_spell_name = unit, 3, spell_name
                -- Big Nukes
                elseif contains_spell(spell_name, AOE_NUKES) then
                    interrupt_target, interrupt_priority, interrupt_spell_name = unit, 4, spell_name
                -- Utility
                elseif contains_spell(spell_name, UTILITY_SPELLS) then
                    interrupt_target, interrupt_priority, interrupt_spell_name = unit, 5, spell_name
                end
            end
        end
    end

    -- Supplement: Check wigs bars for imminent dangerous casts (boss mods)
    local bars = wigs_tracker:get_all()
    for _, bar in ipairs(bars) do
        local bartext = bar.text or ""
        if contains_spell(bartext, CC_SPELLS) or contains_spell(bartext, HEAL_SPELLS) or contains_spell(bartext, FEAR_SPELLS)
            or contains_spell(bartext, AOE_NUKES) or contains_spell(bartext, UTILITY_SPELLS)
        then
            -- Find the nearest enemy that is alive and valid for interrupt
            for _, unit in ipairs(enemies) do
                if unit_helper:is_valid_enemy(unit) and not unit:is_dead() and not unit_helper:is_dummy(unit) then
                    interrupt_target, interrupt_priority, interrupt_spell_name = unit, 10, bartext
                    break
                end
            end
        end
    end

    -- Attempt to interrupt, prioritizing highest Earth Shock available
    local earth_shock_id = get_highest_earth_shock()
    if interrupt_target and earth_shock_id then
        if spell_helper:has_spell_equipped(earth_shock_id)
            and not spell_helper:is_spell_on_cooldown(earth_shock_id)
            and spell_helper:is_spell_in_range(earth_shock_id, player, interrupt_target:get_position(), player:get_position(), interrupt_target:get_position())
            and spell_helper:is_spell_in_line_of_sight(earth_shock_id, player, interrupt_target)
        then
            profiler.start("Interrupt")
            spell_queue:queue_spell_target(earth_shock_id, interrupt_target, 1, "Auto Interrupt: " .. (interrupt_spell_name or "Earth Shock"))
            profiler.stop("Interrupt")
            return
        end
    end
end

return {
    interrupt_logic = interrupt_logic
}