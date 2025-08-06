-- === Project Sylvanas Shaman Plugin ===
-- Main.lua, NO Healer UI Window, only internal healer logic, and comments
-- Solo Leveling Checkmark (DPS logic toggle) in UI
-- AutoAttack Helper + Profiler integration in DPS rotation
-- Lightning Bolt REMOVED from DPS, Lightning Shield only handled by Auto Lightning Shield toggle
-- Imbuements only maintained if enabled in "Auto Weapon Imbue"

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

-- === SHAMAN SPELL IDS ===
local SPELLS = {
    Berserking = 20554,
    ChainLightning = 421,
    EarthShock = 8042,
    EarthShockHighest = 8042,
    FlameShock = 8050,
    FrostShock = 8056,
    LightningBolt = 403,
    Purge = 370,
    AstralRecall = 556,
    GhostWolf = 2645,
    FarSight = 6196,
    LightningShield = 324,
    WaterBreathing = 131,
    WaterWalking = 546,
    AncestralSpirit = 2008,
    CureDisease = 2870,
    CurePoison = 526,
    NaturesSwiftness = 16188,
    Reincarnation = 20608,
    ChainHeal = 1064,
}

-- === SHAMAN SPELL BUFF IDS  ===
local SPELL_BUFFS = {
    Berserking = 26635,    -- Buff applied by Berserking
}

-- === SHAMAN IMBUE RANKS (for auto weapon imbue) ===
local rockbiter_ranks = {
    { spell = 10399, enchant = 503 },
    { spell = 8019,  enchant = 1   },
    { spell = 8018,  enchant = 6   },
    { spell = 8017,  enchant = 29  },
}
local windfury_ranks = {
    { spell = 8232, enchant = 283 },
}
local flametongue_ranks = {
    { spell = 8030, enchant = 3 },  -- Rank 3
    { spell = 8027, enchant = 4 },  -- Rank 2
    { spell = 8024, enchant = 5 },  -- Rank 1
}
local frostbrand_ranks = {
    { spell = 8033, enchant = 2 },  -- Rank 1
}

-- === SHAMAN HEAL SPELLS ===
local HEALING_WAVE_RANKS = {
    [1] = 331,  -- Rank 1
    [2] = 332,  -- Rank 2
    [3] = 547,  -- Rank 3
    [4] = 913,  -- Rank 4
    [5] = 939,  -- Rank 5
    -- [10]=25396  -- Keep this if you want to handle max rank later
}
local LESSER_HEALING_WAVE_RANKS = {
    [1] = 8004,  -- Rank 1 (add more as discovered)
}
local CHAIN_HEAL_RANKS = {
    [1] = 1064,
    [3] = 25423,
}

-- === SHAMAN TOTEMS ===

-- === EARTH TOTEMS ===
local STONESKIN_TOTEM_RANKS = {
    [1] = 8071,
    [2] = 8154,
    [3] = 8155,
}
local STONESKIN_BUFFS = {
    [1] = 8072,
    [2] = 8156,
    [3] = 8157,
}

local STRENGTH_OF_EARTH_TOTEM_RANKS = {
    [1] = 8075,
    [2] = 8160,
}
local STRENGTH_OF_EARTH_BUFFS = {
    [1] = 8076,
    [2] = 8162,
}

local EARTHBIND_TOTEM_RANKS = {
    [1] = 2484,
}
local STONECLAW_TOTEM_RANKS = {
    [1] = 5730,
    [2] = 6390,
}
local TREMOR_TOTEM_RANKS = {
    [1] = 8143,
}

-- === FIRE TOTEMS ===
local SEARING_TOTEM_RANKS = {
    [1] = 3599,
    [2] = 6363,
}
local FIRE_NOVA_TOTEM_RANKS = {
    [1] = 1535,
    [2] = 8498,
}
local MAGMA_TOTEM_RANKS = {
    [1] = 8190,
}

-- === WATER TOTEMS ===
local HEALING_STREAM_TOTEM_RANKS = {
    [1] = 5394,
}
local HEALING_STREAM_BUFFS = {
    [1] = 5672,
}
local MANA_SPRING_TOTEM_RANKS = {
    [1] = 5675,
}
local MANA_SPRING_BUFFS = {
    [1] = 5677,
}
local POISON_CLEANSING_TOTEM_RANKS = {
    [1] = 8166,
}
local FROST_RESISTANCE_TOTEM_RANKS = {
    [1] = 8181,
}
local FROST_RESISTANCE_BUFFS = {
    [1] = 8182,
}

-- === WIND TOTEMS ===
-- (None implemented, add as discovered)

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
local auto_lightning_shield = { value = false }
local healer_mode = { value = false }
local allow_potions = { value = false }
local allow_ooc_heal = { value = false }
local solo_leveling_dps = { value = false } -- DPS checkmark for solo/leveling logic

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
    if not player or not spell_helper:has_spell_equipped(SPELLS.LightningShield) then return false end
    local buffs = player.get_buffs and player:get_buffs() or {}
    for _, buff in ipairs(buffs) do
        if buff.buff_id == SPELLS.LightningShield then return false end
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

-- === HEALER LOGIC (no UI, all logic is internal/automatic, PvE downranking) ===

local function percent_health(unit)
    if not unit then return 100 end
    local max = unit.get_max_health and unit:get_max_health() or 1
    local hp = unit.get_health and unit:get_health() or 1
    return (hp / max) * 100
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

    -- 1. Find all nearby allies (including self)
    local allies = unit_helper:get_ally_list_around(player:get_position(), 100, true, true, false) or {}
    table.insert(allies, player)
    table.sort(allies, function(a, b) return percent_health(a) < percent_health(b) end)
    local target = allies[1]
    if not target or target:is_dead() or (target.is_ghost and target:is_ghost()) then return end

    local hp = percent_health(target)

    -- 2. Group healing: If 3+ allies below 70%, prefer Chain Heal 3 or 1
    local injured_count = 0
    for _, ally in ipairs(allies) do
        if percent_health(ally) < 70 then injured_count = injured_count + 1 end
    end
    if injured_count >= 3 then
        if can_cast_heal(CHAIN_HEAL_RANKS[3], target) then
            spell_queue:queue_spell_target(CHAIN_HEAL_RANKS[3], target, 1, "Chain Heal (R3)")
            return
        elseif can_cast_heal(CHAIN_HEAL_RANKS[1], target) then
            spell_queue:queue_spell_target(CHAIN_HEAL_RANKS[1], target, 1, "Chain Heal (R1)")
            return
        end
    end

    -- 3. Single-target downranking (edit thresholds below to tune behavior)
    if hp < 40 and can_cast_heal(HEALING_WAVE_RANKS[5], target) then
        spell_queue:queue_spell_target(HEALING_WAVE_RANKS[5], target, 1, "Healing Wave R5")
        return
    elseif hp < 70 and can_cast_heal(HEALING_WAVE_RANKS[4], target) then
        spell_queue:queue_spell_target(HEALING_WAVE_RANKS[4], target, 1, "Healing Wave R4")
        return
    elseif hp < 90 and can_cast_heal(HEALING_WAVE_RANKS[1], target) then
        spell_queue:queue_spell_target(HEALING_WAVE_RANKS[1], target, 1, "Healing Wave R1 (cheap/Ancestral Healing)")
        return
    end

    -- 4. Mana regen: If no one needs healing, do nothing (allow 5s rule regen)
end

-- === DPS/ROTATION LOGIC ===
local function shaman_rotation_logic()
    local player = get_local_player()
    if not player then return end

    -- === Auto Lightning Shield ===
    if can_apply_lightning_shield() and spell_helper:has_spell_equipped(SPELLS.LightningShield) then
        spell_queue:queue_spell_target(SPELLS.LightningShield, player, 2, "Auto Lightning Shield")
        return
    end

    -- === Auto Weapon Imbue ===
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

    -- === SOLO LEVELING DPS LOGIC (NO Lightning Bolt/Shield) ===
    if solo_leveling_dps.value then
        -- Priority: Flame Shock > Earth Shock (NO Lightning Bolt, NO Lightning Shield)
        local enemies = unit_helper:get_enemy_list_around(player:get_position(), 30, true, false, false, false)
        local target = nil
        for _, unit in ipairs(enemies) do
            if unit_helper:is_valid_enemy(unit) and not unit:is_dead() and not unit_helper:is_dummy(unit) then
                target = unit
                break
            end
        end
        if target then
            -- AutoAttack Helper: don't cast spells if next swing is within 0.3s
            local next_attack_time = auto_attack_helper:get_next_attack_core_time(player)
            local current_time = auto_attack_helper:get_current_combat_core_time()
            local safe_cast = true
            if next_attack_time and current_time then
                if next_attack_time - current_time < 0.30 then
                    safe_cast = false
                end
            end
            if safe_cast then
                -- Profiler integration
                if spell_helper:has_spell_equipped(SPELLS.FlameShock)
                    and not spell_helper:is_spell_on_cooldown(SPELLS.FlameShock)
                    and spell_helper:is_spell_in_range(SPELLS.FlameShock, player, target:get_position(), player:get_position(), target:get_position())
                    and spell_helper:is_spell_in_line_of_sight(SPELLS.FlameShock, player, target)
                then
                    profiler.start("FlameShock")
                    spell_queue:queue_spell_target(SPELLS.FlameShock, target, 1, "Solo Leveling DPS: Flame Shock")
                    profiler.stop("FlameShock")
                    return
                end
                if spell_helper:has_spell_equipped(SPELLS.EarthShock)
                    and not spell_helper:is_spell_on_cooldown(SPELLS.EarthShock)
                    and spell_helper:is_spell_in_range(SPELLS.EarthShock, player, target:get_position(), player:get_position(), target:get_position())
                    and spell_helper:is_spell_in_line_of_sight(SPELLS.EarthShock, player, target)
                then
                    profiler.start("EarthShock")
                    spell_queue:queue_spell_target(SPELLS.EarthShock, target, 1, "Solo Leveling DPS: Earth Shock")
                    profiler.stop("EarthShock")
                    return
                end
            end
        end
    end
end

-- === MAIN LOGIC ENTRYPOINT ===
local function shaman_plugin_logic()
    if not enable_rotation:get_state() then return end
    if healer_mode.value then
        shaman_healer_logic()
        return
    end
    shaman_rotation_logic()
end
core.register_on_update_callback(shaman_plugin_logic)

-- === UI: Main Window Only (No Healer Window) ===

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
            render_checkbox(shaman_window, "Auto Lightning Shield", auto_lightning_shield, 165)
            render_checkbox(shaman_window, "Solo Leveling DPS Logic", solo_leveling_dps, 195)

            shaman_window:render_text(FONT_MEDIUM, vec2.new(25, 230), color.white(180), "Totem Controls")
            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, 245.0, 0.0, color.white(40))
            end
            render_checkbox(shaman_window, "Auto Stoneskin Totem", {value=false}, 260)
            render_checkbox(shaman_window, "Auto Strength of Earth", {value=false}, 290)
            render_checkbox(shaman_window, "Auto Healing Stream Totem", {value=false}, 320)
            render_checkbox(shaman_window, "Auto Mana Spring Totem", {value=false}, 350)
            render_checkbox(shaman_window, "Auto Tremor Totem", {value=false}, 380)

            shaman_window:render_text(FONT_MEDIUM, vec2.new(25, 415), color.white(180), "Weapon Imbues")
            if shaman_window.add_separator then
                shaman_window:add_separator(3.0, 3.0, 430.0, 0.0, color.white(40))
            end
            render_weapon_imbue_radio(shaman_window, 445)

            local util_y = 570
            shaman_window:render_text(FONT_SMALL, vec2.new(25, util_y), color.white(120), "Coming soon: Advanced DPS options, PvP tools, CC chain, etc.")
        end
    )
end)

--[[ 
    ================================
    === HOW TO ADJUST HEALER LOGIC ==
    ================================
    - To change the Healing Wave Rank 1 auto-cast HP threshold, edit the value of hp < 90 in shaman_healer_logic().
    - To add more healing logic (ex: more ranks, Chain Heal, etc), expand the logic inside shaman_healer_logic().
    - There is NO healer UI/window. All healer logic is now fully automatic, driven only by code.
    - Main window UI controls toggles and weapon imbues only.

    ==========================================
    === SOLO LEVELING DPS LOGIC (NEW)       ==
    ==========================================
    - Toggle the "Solo Leveling DPS Logic" checkbox in the Shaman UI to enable/disable DPS/leveling logic.
    - DPS logic will prioritize Flame Shock > Earth Shock on nearest enemy.
    - Lightning Bolt and Lightning Shield are not included in the solo DPS logic.
    - Imbue spells are controlled by the "Auto Weapon Imbue" checkboxes.
--]]