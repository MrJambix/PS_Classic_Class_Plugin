-- === Project Sylvanas Shaman Plugin ===
-- enhancement_dps_logic.lua

local enhancement_dps_logic = {}

-- Helper to safely determine elite/boss status from available properties
local function is_elite_or_boss(unit)
    if unit.is_boss then return true end
    if unit.is_elite then return true end
    if unit.npc_classification and unit.npc_classification >= 2 then return true end
    return false
end

-- Helper to check if target should be interrupted
local function needs_interrupt(unit)
    local cast_info = unit.get_cast_info and unit:get_cast_info()
    if cast_info and cast_info.is_casting and not cast_info.is_uninterruptible then
        return true
    end
    return false
end

-- Helper to check if Blood Fury is active
local function has_blood_fury_buff(player, SPELL_BUFFS)
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == SPELL_BUFFS.BloodFury then
            return true
        end
    end
    return false
end

-- Helper to check if Elemental Mastery is active
local function has_elemental_mastery_buff(player, SPELL_BUFFS)
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == SPELL_BUFFS.ElementalMastery then
            return true
        end
    end
    return false
end

-- Helper to check if Flame Shock debuff is active on target
local function has_flame_shock_debuff(target, SPELL_BUFFS)
    local debuffs = target.get_debuffs and target:get_debuffs() or {}
    for _, debuff in ipairs(debuffs) do
        if debuff.buff_id == SPELL_BUFFS.FlameShock then
            return true
        end
    end
    return false
end

function enhancement_dps_logic.run(core, spell_helper, unit_helper, spell_queue, profiler, auto_attack_helper, health_prediction,
    auto_tremor_totem, auto_interrupt, auto_lightning_shield, weapon_imbue_state,
    rockbiter_ranks, windfury_ranks, flametongue_ranks, frostbrand_ranks, SPELLS, SPELL_BUFFS)

    local get_local_player = function() return core.object_manager.get_local_player() end
    local player = get_local_player()
    if not player then return end

    -- Find a valid combat target
    local enemies = unit_helper:get_enemy_list_around(player:get_position(), 30, true, false, false, false)
    local target = nil
    for _, unit in ipairs(enemies) do
        if unit_helper:is_valid_enemy(unit)
            and not unit:is_dead()
            and not unit_helper:is_dummy(unit)
            and unit_helper:is_in_combat(unit)
            and unit:is_in_combat()
        then
            target = unit
            break
        end
    end
    if not target then return end

    -- === Auto-attack swing timing ===
    local next_attack_time = auto_attack_helper:get_next_attack_core_time(player)
    local current_time = auto_attack_helper:get_current_combat_core_time()
    local swing_buffer = 0.45 -- seconds
    local can_cast = true
    if next_attack_time and current_time then
        if next_attack_time - current_time < swing_buffer then
            can_cast = false
        end
    end

    -- === INTERRUPT PRIORITY ===
    if needs_interrupt(target) and can_cast then
        -- Interrupt takes precedence over DPS
        local earth_shock_ranks = SPELLS.EarthShock
        for i = #earth_shock_ranks, 1, -1 do
            local earth_id = earth_shock_ranks[i]
            if earth_id and spell_helper:has_spell_equipped(earth_id)
                and not spell_helper:is_spell_on_cooldown(earth_id)
                and spell_helper:is_spell_in_range(earth_id, player, target:get_position(), player:get_position(), target:get_position())
                and spell_helper:is_spell_in_line_of_sight(earth_id, player, target)
            then
                profiler.start("EarthShockInterrupt")
                spell_queue:queue_spell_target(earth_id, target, 1, "Interrupt: Earth Shock")
                profiler.stop("EarthShockInterrupt")
                return -- Do NOT continue DPS logic
            end
        end
    end

    -- === Mana management ===
    local mana_percent = player.get_power_percentage and player:get_power_percentage(0) or 1
    local safe_mana = 0.35 -- Only use shocks if above 35% mana

    -- === Burst Logic ===
    -- Classic Era Burst: Blood Fury, Elemental Mastery, Trinket, Potion, Shocks
    local should_burst = false
    if is_elite_or_boss(target) then
        should_burst = true
    end
    -- Also burst when target is low HP for finish (e.g., below 35%)
    if (unit_helper:get_health_percentage(target) or 1) < 0.35 then
        should_burst = true
    end
    -- You could add: should_burst = burst_mode_enabled

    if should_burst and can_cast then
        -- 1. Blood Fury
        local blood_fury_id = SPELLS.BloodFury[1]
        if spell_helper:has_spell_equipped(blood_fury_id)
            and not spell_helper:is_spell_on_cooldown(blood_fury_id)
            and not has_blood_fury_buff(player, SPELL_BUFFS)
        then
            spell_queue:queue_spell_target(blood_fury_id, player, 1, "Burst: Blood Fury")
        end

        -- 2. Elemental Mastery (if specced)
        local elemental_mastery_id = SPELLS.ElementalMastery and SPELLS.ElementalMastery[1]
        if elemental_mastery_id and spell_helper:has_spell_equipped(elemental_mastery_id)
            and not spell_helper:is_spell_on_cooldown(elemental_mastery_id)
            and not has_elemental_mastery_buff(player, SPELL_BUFFS)
        then
            spell_queue:queue_spell_target(elemental_mastery_id, player, 1, "Burst: Elemental Mastery")
        end

        -- 3. On-use trinket (example, if you track trinket spells)
        local trinket_spell_id = SPELLS.OnUseTrinket and SPELLS.OnUseTrinket[1]
        if trinket_spell_id and spell_helper:has_spell_equipped(trinket_spell_id)
            and not spell_helper:is_spell_on_cooldown(trinket_spell_id)
        then
            spell_queue:queue_spell_target(trinket_spell_id, player, 1, "Burst: Trinket")
        end

        -- 4. Use shock spells (even if mana is low, burst is priority)
        local flame_shock_ranks = SPELLS.FlameShock
        if not has_flame_shock_debuff(target, SPELL_BUFFS) then
            for i = #flame_shock_ranks, 1, -1 do
                local flame_id = flame_shock_ranks[i]
                if flame_id and spell_helper:has_spell_equipped(flame_id)
                    and not spell_helper:is_spell_on_cooldown(flame_id)
                    and spell_helper:is_spell_in_range(flame_id, player, target:get_position(), player:get_position(), target:get_position())
                    and spell_helper:is_spell_in_line_of_sight(flame_id, player, target)
                then
                    profiler.start("FlameShock")
                    spell_queue:queue_spell_target(flame_id, target, 1, "Burst: Flame Shock")
                    profiler.stop("FlameShock")
                    return
                end
            end
        end
        local earth_shock_ranks = SPELLS.EarthShock
        for i = #earth_shock_ranks, 1, -1 do
            local earth_id = earth_shock_ranks[i]
            if earth_id and spell_helper:has_spell_equipped(earth_id)
                and not spell_helper:is_spell_on_cooldown(earth_id)
                and spell_helper:is_spell_in_range(earth_id, player, target:get_position(), player:get_position(), target:get_position())
                and spell_helper:is_spell_in_line_of_sight(earth_id, player, target)
            then
                profiler.start("EarthShock")
                spell_queue:queue_spell_target(earth_id, target, 1, "Burst: Earth Shock")
                profiler.stop("EarthShock")
                return
            end
        end
    end

    -- === NORMAL FIGHT: Only cast shocks if mana is safe, never delay swing, and only if not interrupting or bursting ===
    if can_cast and mana_percent > safe_mana and not should_burst then
        local flame_shock_ranks = SPELLS.FlameShock
        if not has_flame_shock_debuff(target, SPELL_BUFFS) then
            for i = #flame_shock_ranks, 1, -1 do
                local flame_id = flame_shock_ranks[i]
                if flame_id and spell_helper:has_spell_equipped(flame_id)
                    and not spell_helper:is_spell_on_cooldown(flame_id)
                    and spell_helper:is_spell_in_range(flame_id, player, target:get_position(), player:get_position(), target:get_position())
                    and spell_helper:is_spell_in_line_of_sight(flame_id, player, target)
                then
                    profiler.start("FlameShock")
                    spell_queue:queue_spell_target(flame_id, target, 1, "Enhancement DPS: Flame Shock")
                    profiler.stop("FlameShock")
                    return
                end
            end
        end
        local earth_shock_ranks = SPELLS.EarthShock
        for i = #earth_shock_ranks, 1, -1 do
            local earth_id = earth_shock_ranks[i]
            if earth_id and spell_helper:has_spell_equipped(earth_id)
                and not spell_helper:is_spell_on_cooldown(earth_id)
                and spell_helper:is_spell_in_range(earth_id, player, target:get_position(), player:get_position(), target:get_position())
                and spell_helper:is_spell_in_line_of_sight(earth_id, player, target)
            then
                profiler.start("EarthShock")
                spell_queue:queue_spell_target(earth_id, target, 1, "Enhancement DPS: Earth Shock")
                profiler.stop("EarthShock")
                return
            end
        end
    end

    -- Default: Auto-attack is king, do nothing and let white hits do work
end

return enhancement_dps_logic