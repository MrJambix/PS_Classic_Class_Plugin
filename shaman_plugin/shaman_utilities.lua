local spell_helper = require("common/utility/spell_helper")
local spell_queue = require("common/modules/spell_queue")
local shaman_data = require("shaman_spells_buffs")
local SPELLS = shaman_data.SPELLS
local rockbiter_ranks = shaman_data.rockbiter_ranks
local windfury_ranks = shaman_data.windfury_ranks
local flametongue_ranks = shaman_data.flametongue_ranks
local frostbrand_ranks = shaman_data.frostbrand_ranks

local DRINK_BUFF_ID = 430
local function has_drink_buff(player)
    if not player then return false end
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == DRINK_BUFF_ID then
            return true
        end
    end
    return false
end

local function get_highest_imbue_spell_and_enchant(imbue_ranks)
    for _, v in ipairs(imbue_ranks) do
        if spell_helper:has_spell_equipped(v.spell) then
            return v.spell, v.enchant
        end
    end
    return nil, nil
end

local function is_mainhand_imbued_with(player, enchant_id)
    local mainhand = player.get_item_at_inventory_slot and player:get_item_at_inventory_slot(16)
    if not mainhand or not mainhand.object then return false end
    if not mainhand.object.item_has_enchant or not mainhand.object:item_has_enchant() then return false end
    local existing = mainhand.object.item_enchant_id and mainhand.object:item_enchant_id()
    return existing == enchant_id
end

local function auto_weapon_imbue_logic(weapon_imbue_state)
    local player = core.object_manager.get_local_player()
    if not player then return end
    if has_drink_buff(player) then return false end
    local imbue_selected = false
    for k, v in pairs(weapon_imbue_state) do
        if v then imbue_selected = true break end
    end
    if imbue_selected then
        if weapon_imbue_state["rockbiter"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(rockbiter_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Rockbiter")
                return true
            end
        elseif weapon_imbue_state["windfury"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(windfury_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Windfury")
                return true
            end
        elseif weapon_imbue_state["flametongue"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(flametongue_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Flametongue")
                return true
            end
        elseif weapon_imbue_state["frostbrand"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(frostbrand_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Frostbrand")
                return true
            end
        end
    end
    return false
end

local function auto_lightning_shield_logic(enabled)
    if not enabled then return false end
    local player = core.object_manager.get_local_player()
    if not player then return false end
    if has_drink_buff(player) then return false end
    local spell_id = SPELLS.LightningShield[1]
    if not spell_helper:has_spell_equipped(spell_id) then return false end
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == spell_id then
            return false
        end
    end
    spell_queue:queue_spell_target(spell_id, player, 2, "Auto Lightning Shield")
    return true
end

return {
    has_drink_buff = has_drink_buff,
    auto_weapon_imbue_logic = auto_weapon_imbue_logic,
    auto_lightning_shield_logic = auto_lightning_shield_logic
}