-- === Project Sylvanas Shaman Plugin ===
-- Main.lua, NO Healer UI Window, only internal healer logic, and comments
-- Advanced Healer Mode: integrates target_selector and health_prediction APIs
-- Logs mode activation/deactivation for Healer Mode and Solo Leveling DPS Logic
-- Healing logic restricted to self and party members only
-- Now uses shaman_spells_buffs.lua for all spell/buff tables

local core = _G.core
local menu = core.menu

-- === MODULES ===
local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local spell_queue = require("common/modules/spell_queue")
local buff_manager = require("common/modules/buff_manager")
local spell_helper = require("common/utility/spell_helper")
local unit_helper = require("common/utility/unit_helper")
local cooldown_tracker = require("common/utility/cooldown_tracker")
local auto_attack_helper = require("common/utility/auto_attack_helper")
local profiler = require("common/modules/profiler")
local target_selector = require("common/modules/target_selector")
local health_prediction = require("common/modules/health_prediction")

-- === SHAMAN SPELLS & BUFFS TABLES ===
local shaman_data = require("shaman_spells_buffs")
local SPELLS = shaman_data.SPELLS
local rockbiter_ranks = shaman_data.rockbiter_ranks
local windfury_ranks = shaman_data.windfury_ranks
local flametongue_ranks = shaman_data.flametongue_ranks
local frostbrand_ranks = shaman_data.frostbrand_ranks
local SPELL_BUFFS = shaman_data.SPELL_BUFFS

-- === UI Checkbox State Tables (For main window only) ===
local weapon_imbues = {
    { label = "Auto Windfury Weapon", key = "windfury" },
    { label = "Auto Flametongue Weapon", key = "flametongue" },
    { label = "Auto Rockbiter Weapon", key = "rockbiter" },
    { label = "Auto Frostbrand Weapon", key = "frostbrand" },
}
local weapon_imbue_state = { windfury = false, flametongue = false, rockbiter = false, frostbrand = false }

local enable_rotation = menu.checkbox(false, "enable_shaman_rotation")
local enable_logger = menu.checkbox(false, "enable_logger")
local auto_interrupt = { value = false }
local auto_lightning_shield = { value = false }
local auto_tremor_totem = { value = false }
local healer_mode = { value = false }
local allow_potions = { value = false }
local allow_ooc_heal = { value = false }
local solo_leveling_dps = { value = false }

-- === Mode State Tracking for Logging ===
local prev_healer_mode = healer_mode.value
local prev_solo_leveling_dps = solo_leveling_dps.value

local FONT_SMALL = 1
local FONT_MEDIUM = 1

-- === Helper Functions ===

local function get_local_player() return core.object_manager.get_local_player() end

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

local function can_apply_lightning_shield()
    if not auto_lightning_shield.value then return false end
    local player = get_local_player()
    if not player or not spell_helper:has_spell_equipped(SPELLS.LightningShield[1]) then return false end
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == SPELLS.LightningShield[1] then return false end
    end
    return true
end

-- Logger (buffs, spell cast, weapon enchant)
local function log_player_buffs_and_mainhand()
    local player = get_local_player()
    if not player then
        core.log("[Logger] No player object found.")
        return
    end
    local buffs = player.get_buffs and player:get_buffs() or {}
    core.log("[Logger] Active buffs on player:")
    for _, buff in ipairs(buffs) do
        local id = buff.buff_id or buff.spell_id or buff.id or "?"
        local name = buff.buff_name or buff.spell_name or buff.name or "?"
        core.log(string.format("[Logger] Buff: %s (ID: %s)", name, id))
    end
    local mainhand = player.get_item_at_inventory_slot and player:get_item_at_inventory_slot(16)
    if mainhand and mainhand.object then
        local obj = mainhand.object
        local has_enchant = obj.item_has_enchant and obj:item_has_enchant()
        local ench_id = obj.item_enchant_id and obj:item_enchant_id()
        core.log(string.format("[Logger] Main Hand %s: Enchant present: %s, Enchant ID: %s",
            obj.get_name and obj:get_name() or "(Unknown Weapon)", tostring(has_enchant), tostring(ench_id)))
    else
        core.log("[Logger] Main Hand: None equipped")
    end
end

core.register_on_spell_cast_callback(function(data)
    if not enable_logger:get_state() then return end
    local player = get_local_player()
    if data.caster and player and data.caster == player then
        local id = data.spell_id or "?"
        local name = core.spell_book.get_spell_name and core.spell_book.get_spell_name(id) or "?"
        core.log(string.format("[Logger] Spell Cast: %s (ID: %s)", name, id))
    end
end)

core.register_on_render_menu_callback(function()
    menu.tree_node():render("Shaman PlugIn", function()
        enable_rotation:render("Enable Shaman PlugIn", "Toggle rotation on/off and show/hide the Shaman UI")
        enable_logger:render("Enable Logger", "Logs all active buffs, spell casts, and main hand imbue info when you click the button below.")
        if menu.button("log_buffs_button"):render("Log Buffs && Mainhand Now") then
            log_player_buffs_and_mainhand()
        end
    end)
end)

-- === Blood Fury Usage Logic ===
local function has_blood_fury_buff(player)
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == SPELL_BUFFS.BloodFury then
            return true
        end
    end
    return false
end

local function try_blood_fury(player, target)
    local blood_fury_id = SPELLS.BloodFury[1]
    if not spell_helper:has_spell_equipped(blood_fury_id)
        or spell_helper:is_spell_on_cooldown(blood_fury_id)
        or has_blood_fury_buff(player)
    then
        return
    end
    local player_hp = unit_helper:get_health_percentage(player) or 1
    local target_hp = unit_helper:get_health_percentage(target) or 1
    if player_hp < 0.5 then return end
    if not target or target:is_dead() then return end
    if not unit_helper:is_valid_enemy(target) then return end
    if not unit_helper:is_in_combat(target) then return end
    if target_hp < 0.5 then return end
    spell_queue:queue_spell_target(blood_fury_id, player, 1, "Blood Fury (Orc/Troll Racial)")
end

-- === Fears/Sleep Spell Detection (for Tremor Totem) ===
local FEAR_SLEEP_KEYWORDS = { "fear", "terror", "scream", "horrify", "panic", "dread", "sleep" }
local function is_fear_or_sleep_spell(spell_name)
    spell_name = spell_name:lower()
    for _, keyword in ipairs(FEAR_SLEEP_KEYWORDS) do
        if spell_name:find(keyword) then
            return true
        end
    end
    return false
end

local function has_tremor_totem(player)
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == SPELL_BUFFS.TremorTotem then
            return true
        end
    end
    return false
end

local function auto_tremor_totem_logic()
    if not auto_tremor_totem.value then return end
    local player = get_local_player()
    if not player then return end
    local tremor_id = SPELLS.TremorTotem[1]
    if not spell_helper:has_spell_equipped(tremor_id) then return end
    if spell_helper:is_spell_on_cooldown(tremor_id) then return end
    if has_tremor_totem(player) then return end

    local allies = unit_helper:get_ally_list_around(player:get_position(), 60, true, true, false)
    table.insert(allies, player)
    local found = false
    for _, ally in ipairs(allies) do
        local buffs = ally.get_buffs and ally:get_buffs() or {}
        for _, buff in ipairs(buffs) do
            if is_fear_or_sleep_spell(buff.buff_name or "") then
                found = true
                break
            end
        end
        if found then break end

        local cast_info = ally.get_cast_info and ally:get_cast_info()
        if cast_info and cast_info.is_casting and is_fear_or_sleep_spell(cast_info.spell_name or "") then
            found = true
            break
        end
    end
    if found then
        spell_queue:queue_spell_target(tremor_id, player, 2, "Auto Tremor Totem")
    end
end

-- === Interrupt Logic ===
local function interrupt_logic()
    if not auto_interrupt.value then return end
    local player = get_local_player()
    if not player then return end
    local enemies = unit_helper:get_enemy_list_around(player:get_position(), 30, true, false, false, false)
    local interrupt_target = nil
    local highest_priority = nil
    for _, unit in ipairs(enemies) do
        if unit_helper:is_valid_enemy(unit) and not unit:is_dead() and not unit_helper:is_dummy(unit) then
            local cast_info = unit.get_cast_info and unit:get_cast_info()
            if cast_info and cast_info.is_casting and not cast_info.is_uninterruptible then
                local spell_name = cast_info.spell_name or ""
                local spell_type = cast_info.spell_type or ""
                if (spell_type == "HEAL" or spell_name:lower():find("heal")) then
                    interrupt_target, highest_priority = unit, 1
                    break
                elseif (spell_type == "CC" or spell_name:lower():find("fear") or spell_name:lower():find("polymorph") or spell_name:lower():find("sleep")) and not highest_priority then
                    interrupt_target, highest_priority = unit, 2
                end
            end
        end
    end
    local earth_shock_r1 = SPELLS.EarthShock[1]
    if interrupt_target then
        if spell_helper:has_spell_equipped(earth_shock_r1)
            and not spell_helper:is_spell_on_cooldown(earth_shock_r1)
            and spell_helper:is_spell_in_range(earth_shock_r1, player, interrupt_target:get_position(), player:get_position(), interrupt_target:get_position())
            and spell_helper:is_spell_in_line_of_sight(earth_shock_r1, player, interrupt_target)
        then
            profiler.start("Interrupt")
            spell_queue:queue_spell_target(earth_shock_r1, interrupt_target, 1, "Auto Interrupt: Earth Shock R1")
            profiler.stop("Interrupt")
            return
        end
    end
end

-- === HEALER LOGIC (Advanced, internal/automatic, uses APIs, party/self only) ===
local function percent_health(unit)
    return (unit_helper:get_health_percentage(unit) or 1) * 100
end

local function can_cast_heal(spell_id, target)
    local player = get_local_player()
    if not spell_helper:has_spell_equipped(spell_id) then return false end
    if not cooldown_tracker or not cooldown_tracker.is_spell_ready then return true end
    if not cooldown_tracker:is_spell_ready(player, spell_id) then return false end
    if not cooldown_tracker:is_spell_in_range(spell_id, player, target) then return false end
    if not cooldown_tracker:is_spell_los(spell_id, player, target) then return false end
    return true
end

local function shaman_healer_logic()
    local player = get_local_player()
    if not player then return end

    -- Get list of party members (API may differ, adjust as needed)
    local party_members = core.party and core.party.get_party_members and core.party:get_party_members() or {}
    table.insert(party_members, player) -- Always include self

    -- Filter for living/valid units only
    local heal_targets = {}
    for _, unit in ipairs(party_members) do
        if unit and not unit:is_dead() and (not unit.is_ghost or not unit:is_ghost()) then
            table.insert(heal_targets, unit)
        end
    end

    -- Sort by lowest HP
    table.sort(heal_targets, function(a, b) return percent_health(a) < percent_health(b) end)
    local target = heal_targets[1]
    if not target then return end

    local hp = percent_health(target)
    local injured_count = 0
    for _, ally in ipairs(heal_targets) do
        if percent_health(ally) < 70 then injured_count = injured_count + 1 end
    end

    -- Use health_prediction to check incoming damage on each target
    local predicted_danger = {}
    for i, ally in ipairs(heal_targets) do
        local inc_damage = health_prediction:get_incoming_damage(ally, 2)
        predicted_danger[i] = inc_damage or 0
    end

    -- Prioritize Chain Heal if 3+ injured allies or incoming damage to multiple
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

    -- Healing Wave logic, using highest incoming damage prediction
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

-- === DPS/ROTATION LOGIC ===
local function shaman_rotation_logic()
    local player = get_local_player()
    if not player then return end

    auto_tremor_totem_logic()
    interrupt_logic()

    if auto_lightning_shield.value and can_apply_lightning_shield() and spell_helper:has_spell_equipped(SPELLS.LightningShield[1]) then
        spell_queue:queue_spell_target(SPELLS.LightningShield[1], player, 2, "Auto Lightning Shield")
        return
    end

    local imbue_selected = false
    for k, v in pairs(weapon_imbue_state) do
        if v then imbue_selected = true break end
    end
    if imbue_selected then
        if weapon_imbue_state["rockbiter"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(rockbiter_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Rockbiter")
                return
            end
        elseif weapon_imbue_state["windfury"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(windfury_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Windfury")
                return
            end
        elseif weapon_imbue_state["flametongue"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(flametongue_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Flametongue")
                return
            end
        elseif weapon_imbue_state["frostbrand"] then
            local spell_id, enchant_id = get_highest_imbue_spell_and_enchant(frostbrand_ranks)
            if spell_id and enchant_id and not is_mainhand_imbued_with(player, enchant_id) then
                spell_queue:queue_spell_target(spell_id, player, 2, "Auto Imbue: Frostbrand")
                return
            end
        end
    end

    if solo_leveling_dps.value then
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
            try_blood_fury(player, target)

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
                    spell_queue:queue_spell_target(flame_id, target, 1, "Solo Leveling DPS: Flame Shock")
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
                    spell_queue:queue_spell_target(earth_id, target, 1, "Solo Leveling DPS: Earth Shock")
                    profiler.stop("EarthShock")
                    return
                end
            end
        end
    end
end

local function shaman_plugin_logic()
    -- Log toggles for mode activation/deactivation
    if healer_mode.value ~= prev_healer_mode then
        if healer_mode.value then
            core.log("[Shaman] Healer Mode Activated.")
        else
            core.log("[Shaman] Healer Mode Deactivated.")
        end
        prev_healer_mode = healer_mode.value
    end

    if solo_leveling_dps.value ~= prev_solo_leveling_dps then
        if solo_leveling_dps.value then
            core.log("[Shaman] Leveling DPS Logic Activated.")
        else
            core.log("[Shaman] Leveling DPS Logic Deactivated.")
        end
        prev_solo_leveling_dps = solo_leveling_dps.value
    end

    if not enable_rotation:get_state() then return end
    if healer_mode.value then
        shaman_healer_logic()
        return
    end
    shaman_rotation_logic()
end
core.register_on_update_callback(shaman_plugin_logic)

local shaman_window = core.menu.window("Shaman Main Window")
local window_position = {
    x = menu.slider_int(0, 3000, 600, "shaman_window_x"),
    y = menu.slider_int(0, 3000, 300, "shaman_window_y"),
}
local window_size = {
    x = menu.slider_int(0, 2000, 450, "shaman_window_width"),
    y = menu.slider_int(0, 2000, 450, "shaman_window_height"),
}
shaman_window:set_initial_size(vec2.new(window_size.x:get(), window_size.y:get()))
shaman_window:set_initial_position(vec2.new(window_position.x:get(), window_position.y:get()))

local function render_checkbox(window, label, state_table, y)
    local checked = (state_table.get_state and state_table:get_state()) or state_table.value
    local v1, v2 = vec2.new(25, y), vec2.new(50, y+22)
    local is_hover = window:is_mouse_hovering_rect(v1, v2)
    window:render_rect_filled(v1, v2, is_hover and color.green_pale(120) or color.white(60), 2.0)
    window:render_rect(v1, v2, color.white(180), 2.0, 1.5)
    if checked then
        window:render_rect_filled(vec2.new(29, y+4), vec2.new(46, y+18), color.green_pale(255), 2.0)
    end
    window:render_text(FONT_SMALL, vec2.new(60, y+2), color.white(255), label)
    if window:is_rect_clicked(v1, v2) then
        if state_table.get_state and state_table.set_state then
            state_table:set_state(not state_table:get_state())
        elseif state_table.value ~= nil then
            state_table.value = not state_table.value
        end
    end
end

local function render_weapon_imbue_radio(window, y_start)
    local y = y_start
    for _, imbue in ipairs(weapon_imbues) do
        local checked = weapon_imbue_state[imbue.key]
        local v1, v2 = vec2.new(25, y), vec2.new(50, y+22)
        local is_hover = window:is_mouse_hovering_rect(v1, v2)
        window:render_rect_filled(v1, v2, is_hover and color.green_pale(120) or color.white(60), 2.0)
        window:render_rect(v1, v2, color.white(180), 2.0, 1.5)
        if checked then
            window:render_rect_filled(vec2.new(29, y+4), vec2.new(46, y+18), color.green_pale(255), 2.0)
        end
        window:render_text(FONT_SMALL, vec2.new(60, y+2), color.white(255), imbue.label)
        if window:is_rect_clicked(v1, v2) then
            weapon_imbue_state[imbue.key] = not checked
            if weapon_imbue_state[imbue.key] then
                for k, _ in pairs(weapon_imbue_state) do
                    if k ~= imbue.key then weapon_imbue_state[k] = false end
                end
            end
        end
        y = y + 30
    end
end

core.register_on_render_window_callback(function()
    if not enable_rotation or not enable_rotation.get_state or not enable_rotation:get_state() then return end
    shaman_window:set_initial_position(vec2.new(window_position.x:get(), window_position.y:get()))
    shaman_window:set_initial_size(vec2.new(window_size.x:get(), window_size.y:get()))
    shaman_window:begin(
        enums.window_enums and enums.window_enums.window_resizing_flags and enums.window_enums.window_resizing_flags.RESIZE_BOTH_AXIS or 0,
        true,
        color.new(22, 22, 44, 240),
        color.new(100, 150, 255, 200),
        enums.window_enums and enums.window_enums.window_cross_visuals and enums.window_enums.window_cross_visuals.BLUE_THEME or 0,
        function()
            local win_size = shaman_window.get_size and shaman_window:get_size() or vec2.new(window_size.x:get(), window_size.y:get())
            local win_width = win_size.x

            local title = "Shaman UI"
            local text_size = shaman_window.get_text_size and shaman_window:get_text_size(title) or vec2.new(100, 30)
            local tx = (win_width - text_size.x) / 2

            local box_top = 9
            local box_bottom = box_top + text_size.y + 8
            local box_left = tx - 8
            local box_right = tx + text_size.x + 8

            shaman_window:render_rect(vec2.new(box_left, box_top), vec2.new(box_right, box_bottom), color.white(60), 0, 1.0)
            shaman_window:render_text(FONT_MEDIUM, vec2.new(tx, box_top + 4), color.green_pale(255), title)

            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, box_bottom + 2, 0.0, color.new(100, 99, 150, 255))
            end

            shaman_window:render_text(FONT_MEDIUM, vec2.new(25, 45), color.white(180), "General Options")
            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, 60.0, 0.0, color.white(40))
            end
            render_checkbox(shaman_window, "Healer Mode", healer_mode, 75)
            render_checkbox(shaman_window, "Allow Use of Potions", allow_potions, 105)
            render_checkbox(shaman_window, "Allow Out of Combat Healing", allow_ooc_heal, 135)
            render_checkbox(shaman_window, "Solo Leveling DPS Logic", solo_leveling_dps, 165)

            shaman_window:render_text(FONT_MEDIUM, vec2.new(25, 200), color.white(180), "Utility")
            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, 215.0, 0.0, color.white(40))
            end
            render_checkbox(shaman_window, "Auto Interrupt", auto_interrupt, 230)
            render_checkbox(shaman_window, "Auto Lightning Shield", auto_lightning_shield, 260)
            render_checkbox(shaman_window, "Auto Tremor Totem", auto_tremor_totem, 290)

            shaman_window:render_text(FONT_MEDIUM, vec2.new(25, 325), color.white(180), "Totem Controls")
            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, 340.0, 0.0, color.white(40))
            end
            render_checkbox(shaman_window, "Auto Stoneskin Totem", {value=false}, 355)
            render_checkbox(shaman_window, "Auto Strength of Earth", {value=false}, 385)
            render_checkbox(shaman_window, "Auto Healing Stream Totem", {value=false}, 415)
            render_checkbox(shaman_window, "Auto Mana Spring Totem", {value=false}, 445)

            shaman_window:render_text(FONT_MEDIUM, vec2.new(25, 480), color.white(180), "Weapon Imbues")
            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, 495.0, 0.0, color.white(40))
            end
            render_weapon_imbue_radio(shaman_window, 510)

            local util_y = 650
            shaman_window:render_text(FONT_SMALL, vec2.new(25, util_y), color.white(120), "Coming soon: Advanced DPS options, PvP tools, CC chain, etc.")
        end
    )
end)

--[[ 
    ================================
    === HOW TO ADJUST HEALER LOGIC ==
    ================================
    - Healing logic now uses both target_selector and health_prediction APIs for advanced healing decisions.
    - Healing logic now only targets self and party members (never random nearby units).
    - To change the Healing Wave Rank 1 auto-cast HP threshold, edit the value of hp < 90 in shaman_healer_logic().
    - To add more healing logic (ex: more ranks, Chain Heal, etc), expand the logic inside shaman_healer_logic().
    - There is NO healer UI/window. All healer logic is now fully automatic, driven only by code.
    - Main window UI controls toggles and weapon imbues only.

    ==========================================
    === SOLO LEVELING DPS LOGIC (NEW)       ==
    ==========================================
    - Toggle the "Solo Leveling DPS Logic" checkbox in the Shaman UI to enable/disable DPS/leveling logic.
    - DPS logic will prioritize highest rank Flame Shock > Earth Shock on nearest enemy IN COMBAT with you.
    - Lightning Bolt and Lightning Shield are not included in the solo DPS logic.
    - Imbue spells are controlled by the "Auto Weapon Imbue" checkboxes.

    ==========================================
    === AUTO INTERRUPT LOGIC (NEW)          ==
    ==========================================
    - Toggle "Auto Interrupt" in Utility section to enable automatic interrupts.
    - Interrupt logic will use Earth Shock Rank 1 on enemy casts, prioritizing heals, then CCs.
    - "Auto Lightning Shield" checkbox is now under Utility as well.

    ==========================================
    === BLOOD FURY (ORC/TROLL RACIAL)      ==
    ==========================================
    - Blood Fury is used for melee burst, as long as you're above 50% HP and the target is a valid enemy above 50% HP.
    - Will not be used if you already have the buff or the spell is on cooldown.

    ==========================================
    === AUTO TREMOR TOTEM (NEW)            ==
    ==========================================
    - Detects party/self being feared or slept, or those spells being cast on them. Will drop Tremor Totem if needed.
    - All Classic WoW era fear/sleep spells monitored by keywords: "fear", "terror", "scream", "horrify", "panic", "dread", "sleep"
--]]