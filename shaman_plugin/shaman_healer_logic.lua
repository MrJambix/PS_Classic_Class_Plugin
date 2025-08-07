local health_prediction = require("common/modules/health_prediction")
local spell_queue = require("common/modules/spell_queue")
local unit_helper = require("common/utility/unit_helper")
local core = _G.core
local shaman_data = require("shaman_spells_buffs")
local SPELLS = shaman_data.SPELLS

local function can_cast_heal(spell_id, target)
    local player = core.object_manager.get_local_player()
    local cooldown_tracker = require("common/utility/cooldown_tracker")
    local spell_helper = require("common/utility/spell_helper")
    if not spell_helper:has_spell_equipped(spell_id) then return false end
    if not cooldown_tracker or not cooldown_tracker.is_spell_ready then return true end
    if not cooldown_tracker:is_spell_ready(player, spell_id) then return false end
    if not cooldown_tracker:is_spell_in_range(spell_id, player, target) then return false end
    if not cooldown_tracker:is_spell_los(spell_id, player, target) then return false end
    return true
end

local function get_group_members(player)
    local members = {}
    if core.raid and core.raid.get_raid_members then
        local raid = core.raid:get_raid_members()
        for _, unit in ipairs(raid) do table.insert(members, unit) end
    elseif core.party and core.party.get_party_members then
        local party = core.party:get_party_members()
        for _, unit in ipairs(party) do table.insert(members, unit) end
    end
    table.insert(members, player)
    return members
end

local function run()
    local player = core.object_manager.get_local_player()
    if not player then return end

    local group_members = get_group_members(player)
    local heal_targets = {}
    for _, unit in ipairs(group_members) do
        if unit and not unit:is_dead() and (not unit.is_ghost or not unit:is_ghost()) then
            table.insert(heal_targets, unit)
        end
    end

    table.sort(heal_targets, function(a, b)
        return (unit_helper:get_health_percentage(a) or 1) < (unit_helper:get_health_percentage(b) or 1)
    end)
    local target = heal_targets[1]
    if not target then return end

    local percent_health = function(unit)
        return (unit_helper:get_health_percentage(unit) or 1) * 100
    end
    local hp = percent_health(target)
    local injured_count = 0
    for _, ally in ipairs(heal_targets) do
        if percent_health(ally) < 70 then injured_count = injured_count + 1 end
    end

    local predicted_danger = {}
    for i, ally in ipairs(heal_targets) do
        local inc_damage = health_prediction:get_incoming_damage(ally, 2)
        predicted_danger[i] = inc_damage or 0
    end

    local chain_heal_ranks = SPELLS.ChainHeal
    local chain_heal_target = nil
    if injured_count >= 3 then
        chain_heal_target = target
    else
        for i, ally in ipairs(heal_targets) do
            if predicted_danger[i] > (ally:get_max_health() or 1000) * 0.25 then
                chain_heal_target = ally
                break
            end
        end
    end
    if chain_heal_target then
        if can_cast_heal(chain_heal_ranks[4], chain_heal_target) then
            spell_queue:queue_spell_target(chain_heal_ranks[4], chain_heal_target, 1, "Chain Heal (Max, API)")
            return
        elseif can_cast_heal(chain_heal_ranks[3], chain_heal_target) then
            spell_queue:queue_spell_target(chain_heal_ranks[3], chain_heal_target, 1, "Chain Heal (R3, API)")
            return
        elseif can_cast_heal(chain_heal_ranks[2], chain_heal_target) then
            spell_queue:queue_spell_target(chain_heal_ranks[2], chain_heal_target, 1, "Chain Heal (R2, API)")
            return
        elseif can_cast_heal(chain_heal_ranks[1], chain_heal_target) then
            spell_queue:queue_spell_target(chain_heal_ranks[1], chain_heal_target, 1, "Chain Heal (R1, API)")
            return
        end
    end

    local healing_wave_ranks = { [1]=331, [2]=332, [3]=547, [4]=913, [5]=939 }
    local healing_target = target
    local highest_predicted = hp
    for i, ally in ipairs(heal_targets) do
        local predicted = predicted_danger[i]
        if predicted > (ally:get_max_health() or 1000) * 0.25 and percent_health(ally) < highest_predicted then
            healing_target = ally
            highest_predicted = percent_health(ally)
        end
    end
    local hthp = percent_health(healing_target)
    if hthp < 40 and can_cast_heal(healing_wave_ranks[5], healing_target) then
        spell_queue:queue_spell_target(healing_wave_ranks[5], healing_target, 1, "Healing Wave R5 (API)")
        return
    elseif hthp < 70 and can_cast_heal(healing_wave_ranks[4], healing_target) then
        spell_queue:queue_spell_target(healing_wave_ranks[4], healing_target, 1, "Healing Wave R4 (API)")
        return
    elseif hthp < 90 and can_cast_heal(healing_wave_ranks[1], healing_target) then
        spell_queue:queue_spell_target(healing_wave_ranks[1], healing_target, 1, "Healing Wave R1 (API)")
        return
    end
end

return {
    run = run
}