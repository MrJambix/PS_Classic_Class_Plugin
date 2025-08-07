-- === Project Sylvanas Shaman Plugin ===
-- enhancement_dps_logic.lua

local enhancement_dps_logic = {}

function enhancement_dps_logic.run(core, spell_helper, unit_helper, spell_queue, profiler, auto_attack_helper, health_prediction, auto_tremor_totem, auto_interrupt, auto_lightning_shield, weapon_imbue_state, rockbiter_ranks, windfury_ranks, flametongue_ranks, frostbrand_ranks, SPELLS, SPELL_BUFFS)
    local get_local_player = function() return core.object_manager.get_local_player() end
    local player = get_local_player()
    if not player then return end

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
    if target then
        -- Blood Fury Logic
        local blood_fury_id = SPELLS.BloodFury[1]
        local function has_blood_fury_buff(player)
            local buffs = player.get_buffs and player:get_buffs() or {}
            for _, buff in ipairs(buffs) do
                if buff.buff_id == SPELL_BUFFS.BloodFury then
                    return true
                end
            end
            return false
        end

        if spell_helper:has_spell_equipped(blood_fury_id)
            and not spell_helper:is_spell_on_cooldown(blood_fury_id)
            and not has_blood_fury_buff(player)
        then
            local player_hp = unit_helper:get_health_percentage(player) or 1
            local target_hp = unit_helper:get_health_percentage(target) or 1
            if player_hp >= 0.5 and target_hp >= 0.5 then
                spell_queue:queue_spell_target(blood_fury_id, player, 1, "Blood Fury (Orc/Troll Racial)")
                -- Don't return, continue DPS!
            end
        end

        local next_attack_time = auto_attack_helper:get_next_attack_core_time(player)
        local current_time = auto_attack_helper:get_current_combat_core_time()
        local safe_cast = true
        if next_attack_time and current_time then
            if next_attack_time - current_time < 0.30 then
                safe_cast = false
            end
        end
        local flame_shock_ranks = SPELLS.FlameShock
        local earth_shock_ranks = SPELLS.EarthShock
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
end

return enhancement_dps_logic