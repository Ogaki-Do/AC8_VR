--[[
  ============================================================================
  ac8_hud_glow_inspector.lua : HUD Visibility Test Bench (v5.0-VanillaStart)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenVR / OpenXR
  Strict Rule: 100% PURE 7-BIT ASCII ONLY (NO MULTIBYTE / NO GARBLED TEXT)

  Philosophy:
    1. ZERO MODIFICATIONS ON STARTUP (100% VANILLA BASELINE):
       - All tests start in DISABLED state.
       - Master modification switch is OFF by default.
       - Does NOT touch or alter the game's native HUD until user explicitly
         clicks a test.
    2. ATOMIC ISOLATION TESTING:
       - Every test can be activated and deactivated independently.
       - Tests can be toggled ON and OFF in real-time to compare directly
         against the vanilla baseline.
    3. FULL REVERSIBILITY:
       - Stores original baseline snapshots of widgets.
       - Single-click "Revert to Vanilla" button restores all HUD elements
         instantly back to stock.
    4. CRYSTAL-CLEAR DASHBOARD:
       - Top dashboard explicitly announces whether HUD is in VANILLA state
         or which tests are currently active.
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-HUD-BENCH"
local SCRIPT_VER  = "v5.0-VanillaStart"

local function safe_call(fn, default)
    local ok, res = pcall(fn)
    return ok and res or default
end

local function get_safe_name(obj)
    if not obj then return "nil" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or tostring(obj)
end

--------------------------------------------------------------------------
-- 1. Configuration & Test State (ALL DEFAULT TO OFF / VANILLA)
--------------------------------------------------------------------------
local S = {
    -- Master Switch: starts OFF (100% Vanilla Baseline)
    master_active         = false,

    -- Test 1: Black Drop-Shadow on Digits
    test1_black_shadow    = false,
    test1_shadow_offset   = 2.5,

    -- Test 2: Force Opaque Alpha 1.0
    test2_force_opaque    = false,

    -- Test 3: Color Override (1: Native Green, 2: Cyan, 3: Amber, 4: White)
    test3_color_override  = false,
    test3_color_id        = 2, -- Cyan when enabled

    -- Test 4: Engine Bloom Quality (-1: Vanilla Native, 0: OFF, 1: LOW, 5: MAX)
    test4_bloom_override  = false,
    test4_bloom_quality   = 5,

    -- Test 5: HDR Luminance Boost
    test5_hdr_boost       = false,
    test5_hdr_multiplier  = 3.5,

    -- Category Filters (Which instrument groups to apply active tests to)
    apply_to_digits       = true,  -- Speed & Altitude Numbers
    apply_to_ladder       = true,  -- Pitch Ladder & Horizon
    apply_to_reticle      = true,  -- Gun Reticle & Crosshair
    apply_to_weapons      = true,  -- Weapons & Aircraft Status
    apply_to_radar        = true,  -- Radar & MiniMap

    -- Telemetry Widget Counts
    count_digits          = 0,
    count_ladder          = 0,
    count_reticle         = 0,
    count_weapons         = 0,
    count_radar           = 0,
    count_total           = 0,

    dirty                 = false,
}

local COLOR_PALETTE = {
    { id = 1, name = "Vivid Green",  r = 0.05, g = 1.00, b = 0.15 },
    { id = 2, name = "High-Vis Cyan", r = 0.02, g = 0.90, b = 1.00 },
    { id = 3, name = "Solar Amber",   r = 1.00, g = 0.65, b = 0.02 },
    { id = 4, name = "Pure White",    r = 1.00, g = 1.00, b = 1.00 },
}

--------------------------------------------------------------------------
-- 2. Original Widget State Storage (For Clean Vanilla Restoration)
--------------------------------------------------------------------------
local ORIG_STATES = {}

local function snapshot_widget(w, key)
    if not ORIG_STATES[key] then
        local op = safe_call(function() return w:call("GetRenderOpacity") end, 1.0)
        local col = safe_call(function() return w:call("GetColorAndOpacity") end, nil)
        local is_txt = safe_call(function() return w:call("IsA", api:find_uobject("Class /Script/UMG.TextBlock")) end, false)
        local is_img = safe_call(function() return w:call("IsA", api:find_uobject("Class /Script/UMG.Image")) end, false)

        local sh_col = nil
        local sh_off = nil
        if is_txt then
            sh_col = safe_call(function() return w.ShadowColorAndOpacity end, nil)
            sh_off = safe_call(function() return w.ShadowOffset end, nil)
        end

        ORIG_STATES[key] = {
            widget         = w,
            render_opacity = op,
            color_opacity  = col,
            is_text        = is_txt,
            is_image       = is_img,
            shadow_col     = sh_col,
            shadow_off     = sh_off,
        }
    end
end

local function restore_all_to_vanilla()
    -- Restore Engine Bloom to Default
    safe_call(function()
        api:execute_command("r.BloomQuality 5")
        api:execute_command("r.DefaultFeature.Bloom 1")
    end)

    -- Restore Widgets
    for key, state in pairs(ORIG_STATES) do
        local w = state.widget
        if w then
            if state.render_opacity then
                safe_call(function() w:call("SetRenderOpacity", state.render_opacity) end)
            end

            if state.color_opacity then
                safe_call(function() w:call("SetColorAndOpacity", state.color_opacity) end)
                safe_call(function() w:call("SetForegroundColor", state.color_opacity) end)
            else
                safe_call(function() w:call("SetColorAndOpacity", { R=1, G=1, B=1, A=1 }) end)
            end

            if state.is_text then
                if state.shadow_col and state.shadow_off then
                    safe_call(function()
                        w:call("SetShadowColorAndOpacity", state.shadow_col)
                        w:call("SetShadowOffset", state.shadow_off)
                    end)
                else
                    safe_call(function()
                        w:call("SetShadowColorAndOpacity", { R=0, G=0, B=0, A=0 })
                        w:call("SetShadowOffset", { X=0, Y=0 })
                    end)
                end
            end

            safe_call(function()
                local mat = w:call("GetDynamicMaterial")
                if mat then
                    mat:call("SetScalarParameterValue", "Emissive", 1.0)
                    mat:call("SetScalarParameterValue", "Intensity", 1.0)
                    mat:call("SetScalarParameterValue", "Glow", 1.0)
                    mat:call("SetScalarParameterValue", "Brightness", 1.0)
                end
            end)
        end
    end
end

--------------------------------------------------------------------------
-- 3. Widget Processor (Applies Only Active Tests)
--------------------------------------------------------------------------
local function process_widget(w, col_to_apply, shadow_to_apply, s_offset, depth)
    if w == nil or (depth or 0) > 5 then return end
    depth = depth or 0

    local w_key = get_safe_name(w)
    snapshot_widget(w, w_key)

    -- Test 2 & Test 3 & Test 5: Color, Alpha, and Luminance
    if col_to_apply ~= nil then
        safe_call(function() w:call("SetColorAndOpacity", col_to_apply) end)
        safe_call(function() w:call("SetForegroundColor", col_to_apply) end)

        local is_image = safe_call(function() return w:call("IsA", api:find_uobject("Class /Script/UMG.Image")) end, false)
        if is_image then
            safe_call(function()
                local slate_col = { SpecifiedColor = col_to_apply, ColorUseRule = 0 }
                w:call("SetBrushTintColor", slate_col)
            end)
        end
    end

    -- Test 2: Force Opaque Alpha
    if S.test2_force_opaque then
        safe_call(function() w:call("SetRenderOpacity", 1.0) end)
    end

    -- Test 1: Black Text Shadow
    local is_text = safe_call(function() return w:call("IsA", api:find_uobject("Class /Script/UMG.TextBlock")) end, false)
    if is_text then
        if S.test1_black_shadow and shadow_to_apply ~= nil then
            safe_call(function()
                w:call("SetShadowColorAndOpacity", shadow_to_apply)
                w:call("SetShadowOffset", { X = s_offset, Y = s_offset })
            end)
        else
            safe_call(function()
                w:call("SetShadowColorAndOpacity", { R = 0, G = 0, B = 0, A = 0 })
            end)
        end
    end

    -- Dynamic Material Emissive Boost (Test 5)
    if S.test5_hdr_boost and col_to_apply ~= nil then
        safe_call(function()
            local mat = w:call("GetDynamicMaterial")
            if mat ~= nil then
                local lum = col_to_apply.G or col_to_apply.R or 1.0
                mat:call("SetScalarParameterValue", "Emissive", lum)
                mat:call("SetScalarParameterValue", "Intensity", lum)
                mat:call("SetScalarParameterValue", "Glow", lum)
                mat:call("SetScalarParameterValue", "Brightness", lum)
                mat:call("SetVectorParameterValue", "Color", col_to_apply)
                mat:call("SetVectorParameterValue", "EmissiveColor", col_to_apply)
            end
        end)
    end

    -- Recurse children
    local count = safe_call(function() return w:call("GetChildrenCount") end, 0) or 0
    if count > 0 then
        for i = 0, math.min(count - 1, 25) do
            local ch = safe_call(function() return w:call("GetChildAt", i) end, nil)
            if ch ~= nil then
                process_widget(ch, col_to_apply, shadow_to_apply, s_offset, depth + 1)
            end
        end
    end
end

--------------------------------------------------------------------------
-- 4. Pipeline Execution
--------------------------------------------------------------------------
local function apply_pipeline()
    -- IF MASTER IS OFF: Ensure HUD is 100% Vanilla
    if not S.master_active then
        restore_all_to_vanilla()
        S.dirty = false
        return
    end

    -- Test 4: Engine Bloom
    if S.test4_bloom_override then
        safe_call(function()
            api:execute_command("r.BloomQuality " .. tostring(S.test4_bloom_quality))
            api:execute_command("r.DefaultFeature.Bloom " .. (S.test4_bloom_quality > 0 and "1" or "0"))
        end)
    end

    -- Determine Color to Apply (if Test 2, Test 3, or Test 5 active)
    local col_to_apply = nil
    if S.test2_force_opaque or S.test3_color_override or S.test5_hdr_boost then
        local pal = COLOR_PALETTE[S.test3_color_id] or COLOR_PALETTE[1]
        if not S.test3_color_override then
            -- Use Green if color override not checked
            pal = COLOR_PALETTE[1]
        end

        local mult  = S.test5_hdr_boost and S.test5_hdr_multiplier or 1.0
        local alpha = S.test2_force_opaque and 1.0 or 0.85

        col_to_apply = {
            R = pal.r * mult,
            G = pal.g * mult,
            B = pal.b * mult,
            A = alpha,
            r = pal.r * mult,
            g = pal.g * mult,
            b = pal.b * mult,
            a = alpha,
        }
    end

    -- Shadow Color (Test 1)
    local shadow_to_apply = nil
    if S.test1_black_shadow then
        shadow_to_apply = { R = 0.0, G = 0.0, B = 0.0, A = 1.0, r = 0.0, g = 0.0, b = 0.0, a = 1.0 }
    end

    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return end
    local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}

    local cnt_dig = 0
    local cnt_lad = 0
    local cnt_ret = 0
    local cnt_wep = 0
    local cnt_rad = 0
    local cnt_tot = 0

    for _, w in ipairs(all_w) do
        local wn = get_safe_name(w)
        if wn:find("/Engine/Transient", 1, true) and not wn:find("Default__", 1, true) then
            local applied = false

            -- 1. Digits (Speed, Altitude, Digits)
            if S.apply_to_digits and (wn:find("Altitude", 1, true) or wn:find("Speed", 1, true) or wn:find("Altimeter", 1, true) or wn:find("Velocity", 1, true) or wn:find("ValueText", 1, true) or wn:find("Text_Body", 1, true)) then
                process_widget(w, col_to_apply, shadow_to_apply, S.test1_shadow_offset, 0)
                cnt_dig = cnt_dig + 1
                applied = true
            end

            -- 2. Pitch Ladder & Horizon
            if S.apply_to_ladder and (wn:find("PitchMeter", 1, true) or wn:find("LandingGuide", 1, true) or wn:find("FlightPath", 1, true) or wn:find("Horizon", 1, true)) then
                process_widget(w, col_to_apply, shadow_to_apply, S.test1_shadow_offset, 0)
                cnt_lad = cnt_lad + 1
                applied = true
            end

            -- 3. Gun Reticle & Crosshair
            if S.apply_to_reticle and (wn:find("GunReticle", 1, true) or wn:find("Reticle", 1, true) or wn:find("Crosshair", 1, true) or wn:find("Sight", 1, true) or wn:find("Pipper", 1, true)) then
                process_widget(w, col_to_apply, shadow_to_apply, S.test1_shadow_offset, 0)
                cnt_ret = cnt_ret + 1
                applied = true
            end

            -- 4. Weapons & Aircraft Info
            if S.apply_to_weapons and (wn:find("Weapon", 1, true) or wn:find("Flare", 1, true) or wn:find("PlayerState", 1, true) or wn:find("PlayerStatus", 1, true) or wn:find("Plane", 1, true) or wn:find("Armament", 1, true)) then
                process_widget(w, col_to_apply, shadow_to_apply, S.test1_shadow_offset, 0)
                cnt_wep = cnt_wep + 1
                applied = true
            end

            -- 5. Radar & MiniMap
            if S.apply_to_radar and (wn:find("Radar", 1, true) or wn:find("MiniMap", 1, true) or wn:find("RadarCircle", 1, true)) then
                process_widget(w, col_to_apply, shadow_to_apply, S.test1_shadow_offset, 0)
                cnt_rad = cnt_rad + 1
                applied = true
            end

            if applied then
                cnt_tot = cnt_tot + 1
            end
        end
    end

    S.count_digits  = cnt_dig
    S.count_ladder  = cnt_lad
    S.count_reticle = cnt_ret
    S.count_weapons = cnt_wep
    S.count_radar   = cnt_rad
    S.count_total   = cnt_tot
    S.dirty         = false
end

--------------------------------------------------------------------------
-- 5. Tick Loop
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic scan of counts every 180 ticks (~3s)
    if S.dirty or (tick_count % 180 == 0) then
        apply_pipeline()
    end
end)

--------------------------------------------------------------------------
-- 6. ImGui Control Panel (100% PURE ASCII ONLY)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("================================================================")
    imgui.text("       AC8 HUD VISIBILITY TEST BENCH (" .. SCRIPT_VER .. ")")
    imgui.text("================================================================")

    -- =========================================================================
    -- TOP DASHBOARD: EXPLICIT RUNTIME STATE
    -- =========================================================================
    if not S.master_active then
        imgui.text_colored(">>> CURRENT STATUS: [ 100 PERCENT VANILLA DEFAULT - NO MODS ACTIVE ] <<<", 0xFF00FFCC)
        imgui.text("  The game HUD is untouched. Select tests below to apply changes.")
    else
        imgui.text_colored(">>> CURRENT STATUS: [ MODIFICATIONS ACTIVE ] <<<", 0xFFFFFF00)
    end

    imgui.separator()

    -- Master Toggle Button
    if not S.master_active then
        if imgui.button("[ MASTER SWITCH: OFF ] --> Click to ACTIVATE Modifications##master_btn") then
            S.master_active = true
            S.dirty = true
        end
    else
        if imgui.button("[ MASTER SWITCH: ON ]  --> Click to DEACTIVATE (Return to Vanilla)##master_btn") then
            S.master_active = false
            S.test1_black_shadow   = false
            S.test2_force_opaque   = false
            S.test3_color_override = false
            S.test4_bloom_override = false
            S.test5_hdr_boost      = false
            S.dirty = true
        end
    end

    imgui.separator()

    -- =========================================================================
    -- LIVE TEST STATE BADGES
    -- =========================================================================
    imgui.text_colored("--- CURRENT TEST STATES ---", 0xFF00FFCC)

    -- Test 1
    if S.test1_black_shadow and S.master_active then
        imgui.text_colored(string.format("  [TEST 1] Black Text Shadow : [ ACTIVE  (Offset: %.1f px) ]", S.test1_shadow_offset), 0xFF44FF44)
    else
        imgui.text_colored("  [TEST 1] Black Text Shadow : [ OFF / Vanilla ]", 0xFFAAAAAA)
    end

    -- Test 2
    if S.test2_force_opaque and S.master_active then
        imgui.text_colored("  [TEST 2] Force Opaque Alpha: [ ACTIVE  (Alpha: 1.0 Solid) ]", 0xFF44FF44)
    else
        imgui.text_colored("  [TEST 2] Force Opaque Alpha: [ OFF / Vanilla ]", 0xFFAAAAAA)
    end

    -- Test 3
    if S.test3_color_override and S.master_active then
        local cname = (COLOR_PALETTE[S.test3_color_id] or COLOR_PALETTE[2]).name
        imgui.text_colored(string.format("  [TEST 3] HUD Color Hue     : [ ACTIVE: %s ]", cname:upper()), 0xFF00FFFF)
    else
        imgui.text_colored("  [TEST 3] HUD Color Hue     : [ OFF / Vanilla Green ]", 0xFFAAAAAA)
    end

    -- Test 4
    if S.test4_bloom_override and S.master_active then
        local bname = (S.test4_bloom_quality == 0 and "QUALITY 0: Bloom OFF (Sharp)" or (S.test4_bloom_quality == 1 and "QUALITY 1: Low Bloom" or "QUALITY 5: Max Bloom"))
        imgui.text_colored(string.format("  [TEST 4] Engine Bloom Mode : [ ACTIVE: %s ]", bname), 0xFFFFFF00)
    else
        imgui.text_colored("  [TEST 4] Engine Bloom Mode : [ OFF / Vanilla Engine Default ]", 0xFFAAAAAA)
    end

    -- Test 5
    if S.test5_hdr_boost and S.master_active then
        imgui.text_colored(string.format("  [TEST 5] HDR Luminance Glow: [ ACTIVE: %.1fx Multiplier ]", S.test5_hdr_multiplier), 0xFFFF44FF)
    else
        imgui.text_colored("  [TEST 5] HDR Luminance Glow: [ OFF / Vanilla 1.0x ]", 0xFFAAAAAA)
    end

    if S.master_active then
        imgui.text_colored(string.format("  * Controlled Widgets: [%d Total] (Digits:%d, Ladder:%d, Reticle:%d, Weapons:%d, Radar:%d)",
            S.count_total, S.count_digits, S.count_ladder, S.count_reticle, S.count_weapons, S.count_radar), 0xFFCCCCCC)
    end

    imgui.separator()

    -- =========================================================================
    -- INDIVIDUAL ATOMIC TEST BUTTONS
    -- =========================================================================
    imgui.text_colored("--- TEST 1: BLACK DROP-SHADOW (TEXT OUTLINE) ---", 0xFFFFFF00)
    local t1_label = S.test1_black_shadow and "[ TEST 1: BLACK SHADOW ] --> Currently [ ON ] (Click to Turn OFF)##b1"
                                         or "[ TEST 1: BLACK SHADOW ] --> Currently [ OFF ] (Click to Turn ON)##b1"
    if imgui.button(t1_label) then
        S.test1_black_shadow = not S.test1_black_shadow
        if S.test1_black_shadow then S.master_active = true end
        S.dirty = true
    end
    if S.test1_black_shadow then
        local cs, vs = imgui.slider_float("Shadow Thickness px##s_off", S.test1_shadow_offset, 1.0, 5.0)
        if cs then S.test1_shadow_offset = vs; S.dirty = true end
        imgui.text("  Adds black outline behind Speed/Altitude. Cuts through white clouds!")
    end

    imgui.separator()

    imgui.text_colored("--- TEST 2: FORCE OPAQUE ALPHA 1.0 (NO TRANSLUCENCY) ---", 0xFFFFFF00)
    local t2_label = S.test2_force_opaque and "[ TEST 2: FORCE OPAQUE ] --> Currently [ ON ] (Click to Turn OFF)##b2"
                                         or "[ TEST 2: FORCE OPAQUE ] --> Currently [ OFF ] (Click to Turn ON)##b2"
    if imgui.button(t2_label) then
        S.test2_force_opaque = not S.test2_force_opaque
        if S.test2_force_opaque then S.master_active = true end
        S.dirty = true
    end
    imgui.text("  Removes semi-transparent wash. Renders solid color over clouds.")

    imgui.separator()

    imgui.text_colored("--- TEST 3: HIGH-VIS COLOR SHIFT ---", 0xFFFFFF00)
    local t3_label = S.test3_color_override and "[ TEST 3: COLOR SHIFT ]  --> Currently [ ON ] (Click to Turn OFF)##b3"
                                           or "[ TEST 3: COLOR SHIFT ]  --> Currently [ OFF ] (Click to Turn ON)##b3"
    if imgui.button(t3_label) then
        S.test3_color_override = not S.test3_color_override
        if S.test3_color_override then S.master_active = true end
        S.dirty = true
    end
    if S.test3_color_override then
        for _, p in ipairs(COLOR_PALETTE) do
            local is_sel = (S.test3_color_id == p.id)
            local plbl = (is_sel and ">> [ACTIVE] " or "   [ ] ") .. p.name .. "##pal_" .. p.id
            if imgui.button(plbl) then
                S.test3_color_id = p.id
                S.dirty = true
            end
            imgui.same_line()
        end
        imgui.new_line()
    end

    imgui.separator()

    imgui.text_colored("--- TEST 4: ENGINE BLOOM QUALITY (r.BloomQuality) ---", 0xFFFFFF00)
    if imgui.button((S.test4_bloom_override and S.test4_bloom_quality == 0 and ">> [ACTIVE] " or "   ") .. "Bloom OFF (0: Sharp)##b0") then
        S.test4_bloom_override = true
        S.test4_bloom_quality  = 0
        S.master_active        = true
        S.dirty                = true
    end
    imgui.same_line()
    if imgui.button((S.test4_bloom_override and S.test4_bloom_quality == 1 and ">> [ACTIVE] " or "   ") .. "Bloom LOW (1)##b1") then
        S.test4_bloom_override = true
        S.test4_bloom_quality  = 1
        S.master_active        = true
        S.dirty                = true
    end
    imgui.same_line()
    if imgui.button((S.test4_bloom_override and S.test4_bloom_quality == 5 and ">> [ACTIVE] " or "   ") .. "Bloom MAX (5: Neon)##b5") then
        S.test4_bloom_override = true
        S.test4_bloom_quality  = 5
        S.master_active        = true
        S.dirty                = true
    end
    imgui.same_line()
    if imgui.button("Reset Bloom to Vanilla##b_rst") then
        S.test4_bloom_override = false
        safe_call(function()
            api:execute_command("r.BloomQuality 5")
            api:execute_command("r.DefaultFeature.Bloom 1")
        end)
        S.dirty = true
    end

    imgui.separator()

    imgui.text_colored("--- TEST 5: HDR LUMINANCE BOOST (TARGET MARKER GLOW) ---", 0xFFFFFF00)
    local t5_label = S.test5_hdr_boost and "[ TEST 5: HDR BOOST ]    --> Currently [ ON ] (Click to Turn OFF)##b5"
                                       or "[ TEST 5: HDR BOOST ]    --> Currently [ OFF ] (Click to Turn ON)##b5"
    if imgui.button(t5_label) then
        S.test5_hdr_boost = not S.test5_hdr_boost
        if S.test5_hdr_boost then S.master_active = true end
        S.dirty = true
    end
    if S.test5_hdr_boost then
        local cm, vm = imgui.slider_float("Multiplier##m_val", S.test5_hdr_multiplier, 1.0, 15.0)
        if cm then S.test5_hdr_multiplier = vm; S.dirty = true end
        if imgui.button("2.0x (Mild)##m2") then S.test5_hdr_multiplier = 2.0; S.dirty = true end
        imgui.same_line()
        if imgui.button("3.5x (Target Glow)##m35") then S.test5_hdr_multiplier = 3.5; S.dirty = true end
        imgui.same_line()
        if imgui.button("6.0x (Neon)##m6") then S.test5_hdr_multiplier = 6.0; S.dirty = true end
        imgui.same_line()
        if imgui.button("10.0x (Max)##m10") then S.test5_hdr_multiplier = 10.0; S.dirty = true end
    end

    imgui.separator()

    -- =========================================================================
    -- CATEGORY INSTRUMENT SELECTION
    -- =========================================================================
    imgui.text_colored("--- TARGET INSTRUMENT GROUPS ---", 0xFFFFFF00)
    local cd, vd = imgui.checkbox("Speed & Altitude Numbers##cg_dig", S.apply_to_digits)
    if cd then S.apply_to_digits = vd; S.dirty = true end

    imgui.same_line()
    local cl, vl = imgui.checkbox("Pitch Ladder & Horizon##cg_lad", S.apply_to_ladder)
    if cl then S.apply_to_ladder = vl; S.dirty = true end

    local cr, vr = imgui.checkbox("Gun Reticle & Crosshair##cg_ret", S.apply_to_reticle)
    if cr then S.apply_to_reticle = vr; S.dirty = true end

    imgui.same_line()
    local cw, vw = imgui.checkbox("Weapons & Status##cg_wep", S.apply_to_weapons)
    if cw then S.apply_to_weapons = vw; S.dirty = true end

    local cra, vra = imgui.checkbox("Radar & MiniMap##cg_rad", S.apply_to_radar)
    if cra then S.apply_to_radar = vra; S.dirty = true end

    imgui.separator()

    -- =========================================================================
    -- INSTANT REVERT BUTTON
    -- =========================================================================
    if imgui.button("[ REVERT ALL TO 100 PERCENT VANILLA DEFAULTS ]##btn_revert_all") then
        S.master_active        = false
        S.test1_black_shadow   = false
        S.test2_force_opaque   = false
        S.test3_color_override = false
        S.test4_bloom_override = false
        S.test5_hdr_boost      = false
        restore_all_to_vanilla()
        S.dirty = true
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        local ok, err = pcall(render_ui)
        if not ok then
            imgui.text("UI ERROR: " .. tostring(err))
        end
    end)
end

print(string.format("[%s] Loaded successfully (%s). Initial state: 100%% Vanilla.", SCRIPT_NAME, SCRIPT_VER))
