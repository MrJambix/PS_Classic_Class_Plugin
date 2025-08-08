-- === Project Sylvanas Shaman Plugin ===

local core = _G.core
local menu = core.menu

local color = require("common/color")
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local spell_queue = require("common/modules/spell_queue")
local buff_manager = require("common/modules/buff_manager")
local spell_helper = require("common/utility/spell_helper")
local unit_helper = require("common/utility/unit_helper")
local auto_attack_helper = require("common/utility/auto_attack_helper")
local profiler = require("common/modules/profiler")
local target_selector = require("common/modules/target_selector")
local health_prediction = require("common/modules/health_prediction")
local wigs_tracker = require("common/utility/wigs_tracker")

local shaman_data = require("shaman_spells_buffs")
local SPELLS = shaman_data.SPELLS
local rockbiter_ranks = shaman_data.rockbiter_ranks
local windfury_ranks = shaman_data.windfury_ranks
local flametongue_ranks = shaman_data.flametongue_ranks
local frostbrand_ranks = shaman_data.frostbrand_ranks
local SPELL_BUFFS = shaman_data.SPELL_BUFFS

local enhancement_dps_logic = require("enhancement_dps_logic")
local healer_logic = require("shaman_healer_logic")
local shaman_utils = require("shaman_utilities")

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
local enhancement_dps = { value = false }

local prev_healer_mode = healer_mode.value
local prev_enhancement_dps = enhancement_dps.value

local FONT_SMALL = 1
local FONT_MEDIUM = 1

local function get_local_player() return core.object_manager.get_local_player() end

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

-- Create the Shaman UI window object
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

-- === Menu Tree Node for Plugin and Open UI Button ===
core.register_on_render_menu_callback(function()
    menu.tree_node():render("Shaman PlugIn", function()
        enable_rotation:render("Enable Shaman PlugIn", "Toggle rotation on/off and show/hide the Shaman UI")
        enable_logger:render("Enable Logger", "Logs all active buffs, spell casts, and main hand imbue info when you click the button below.")
        if menu.button("log_buffs_button"):render("Log Buffs && Mainhand Now") then
            log_player_buffs_and_mainhand()
        end
        -- Add the Open Shaman UI Window button (uses window API, not a variable)
        if menu.button("open_shaman_ui_button"):render("Open Shaman UI Window") then
            shaman_window:set_visibility(true)
            shaman_window:set_focus()
        end
    end)
end)

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

-- === Interrupt Logic (Wigs/Boss Mods enhanced) ===

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
    local player = get_local_player()
    if not player then return end

    local enemies = unit_helper:get_enemy_list_around(player:get_position(), 30, true, false, false, false)
    local interrupt_target, interrupt_priority = nil, nil
    local interrupt_spell_name = nil

    -- Scan for casting enemies (in combat)
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
    if not shaman_window:is_being_shown() then return end
    shaman_window:set_initial_position(vec2.new(window_position.x:get(), window_position.y:get()))
    shaman_window:set_initial_size(vec2.new(window_size.x:get(), window_size.y:get()))
    local window_open = shaman_window:begin(
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
            render_checkbox(shaman_window, "Enhancement DPS Logic", enhancement_dps, 165)

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
    -- Hide window if X is clicked
    if not window_open then
        shaman_window:set_visibility(false)
    end
end)

-- === Main plugin update/rotation loop ===
local function shaman_plugin_logic()
    if healer_mode.value ~= prev_healer_mode then
        if healer_mode.value then
            core.log("[Shaman] Healer Mode Activated.")
        else
            core.log("[Shaman] Healer Mode Deactivated.")
        end
        prev_healer_mode = healer_mode.value
    end

    if enhancement_dps.value ~= prev_enhancement_dps then
        if enhancement_dps.value then
            core.log("[Shaman] Enhancement DPS Logic Activated.")
        else
            core.log("[Shaman] Enhancement DPS Logic Deactivated.")
        end
        prev_enhancement_dps = enhancement_dps.value
    end

    if not enable_rotation:get_state() then return end

    -- Weapon imbue logic
    if shaman_utils.auto_weapon_imbue_logic(weapon_imbue_state) then return end

    -- Lightning shield logic
    if shaman_utils.auto_lightning_shield_logic(auto_lightning_shield.value) then return end

    -- Tremor totem logic
    auto_tremor_totem_logic()

    -- Interrupt logic
    interrupt_logic()

    if healer_mode.value then
        healer_logic.run()
        return
    end
    if enhancement_dps.value then
        enhancement_dps_logic.run(
            core, spell_helper, unit_helper, spell_queue, profiler, auto_attack_helper, health_prediction,
            auto_tremor_totem, auto_interrupt, auto_lightning_shield, weapon_imbue_state,
            rockbiter_ranks, windfury_ranks, flametongue_ranks, frostbrand_ranks, SPELLS, SPELL_BUFFS
        )
        return
    end
end
core.register_on_update_callback(shaman_plugin_logic)

--[[ 
    ================================
    === HOW TO ADJUST HEALER LOGIC ==
    ================================
    - Healing logic now uses both target_selector and health_prediction APIs for advanced healing decisions.
    - Healing logic now only targets self and party members (never random nearby units).
    - To change the Healing Wave Rank 1 auto-cast HP threshold, edit the value of hp < 90 in Logic.healer_mode().
    - To add more healing logic (ex: more ranks, Chain Heal, etc), expand the logic inside Logic.healer_mode().
    - There is NO healer UI/window. All healer logic is now fully automatic, driven only by code.
    - Main window UI controls toggles and weapon imbues only.

    ==========================================
    === ENHANCEMENT DPS LOGIC (NEW)         ==
    ==========================================
    - Toggle "Enhancement DPS Logic" checkbox in the Shaman UI to enable/disable DPS/leveling logic.
    - DPS logic will prioritize highest rank Flame Shock > Earth Shock on nearest enemy IN COMBAT with you.
    - Uses Blood Fury logic for burst, if available and HP is safe.
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