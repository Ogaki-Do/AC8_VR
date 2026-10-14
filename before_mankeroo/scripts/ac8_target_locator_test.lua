--[[
  ============================================================================
  ac8_target_locator_test.lua : MissileIndicator Restored & Native 2D HUD Ring (v16)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Design:     
    1. IMMEDIATE RESTORATION OF MissileRangeIndicator:
       - Automatically restores MissileRangeIndicator to its original defaults:
         Pos = (0.0, 0.0), Scale = (1.0, 1.0), Angle = 0.0, Slot Size = (30, 20),
         Vis = 3 (HitTestInvisible), Opacity = 1.0.
       - Permanently removes all overrides on MissileRangeIndicator!
    2. RESOLUTION OF 3D TARGET PIN:
       - Memory telemetry confirmed that 3D TargetPin (ClockTargetPinBillboardImage)
         is bound to enemy actor 3.6km in the sky and overridden every frame by
         game C++ Tick (causing POSITION DRIFT: -139397, -889530, 880).
       - Therefore, the proven PitchLadder solution (2D UMG widget shift) is used:
         * Target A: Locator_Wingman (Official native arrow image widget)
         * Target B: WBP_LocatorWidget (Official C++ Slate locator widget)
    3. ACCURATE 360-DEGREE TRACKING (safe_atan2):
       - Azimuth +90 deg -> Points exactly RIGHT (0 deg)
       - Elevation +90 deg -> Points exactly UP (-90 deg)
       - Azimuth -90 deg -> Points exactly LEFT (180 deg)
       - Elevation -90 deg -> Points exactly DOWN (+90 deg)
    4. ZERO-SCROLL COMPACT UI:
       - Fits 100% in UEVR menu without scrolling down!

  Safety:     100% Pure ASCII, Game-Thread Only (on_post_engine_tick), Crash-Safe
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Locator-Lab"
local SCRIPT_VER  = "v16-RestoredAndRing"

local function safe_call(fn, default)
    local ok, res = pcall(fn)
    return ok and res or default
end

local function get_safe_name(obj)
    if not obj then return "nil" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or tostring(obj)
end

local function get_short_name(obj)
    local fn = get_safe_name(obj)
    return fn:match("([^.]+)$") or fn
end

local function is_valid(obj)
    if not obj then return false end
    local ok, cls = pcall(function() return obj:get_class() end)
    return ok and cls ~= nil
end

local function num_field(o, names)
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return o[n] end)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

-- Robust 2-argument atan2 for all Lua versions (Lua 5.1, LuaJIT, Lua 5.4)
local function safe_atan2(y, x)
    if math.atan2 ~= nil then
        return math.atan2(y, x)
    end
    return math.atan(y, x)
end

-- -----------------------------------------------------------------------------
-- State Table
-- -----------------------------------------------------------------------------
local S = {
    enabled                 = true,
    force_test_display      = true,
    target_mode             = 1,       -- 1: Locator_Wingman (Arrow Image), 2: WBP_LocatorWidget (Slate)

    -- PitchLadder HUD Center Basis (Confirmed by v19 ladder fix)
    center_x                = 690.0,
    center_y                = 756.0,
    ring_radius             = 220.0,
    scale                   = 1.5,     -- 1.5x for easy spotting
    opacity                 = 1.0,
    slot_w                  = 240.0,
    slot_h                  = 240.0,
    angle_fine_tune         = 0.0,     -- Fine tune rotation angle
    texture_base_heading    = 0.0,     -- Texture default angle (0 = pointing right)
    offscreen_threshold_deg = 12.0,

    -- Telemetry
    pawn                    = nil,
    target_actor            = nil,
    target_name             = "None",
    target_dist_m           = 0,
    azimuth_deg             = 0.0,
    elevation_deg           = 0.0,
    screen_bearing_deg      = 0.0,     -- Angle on HUD plane: 0=Right, -90=Up, 180=Left, +90=Down
    arrow_heading_deg       = 0.0,     -- Computed rotation angle for arrow
    is_offscreen            = false,

    -- Discovered Handles
    wingman_img             = nil,
    wingman_parent          = nil,
    wbp_locator             = nil,
    wbp_locator_parent      = nil,
    wbp_world_canvas        = nil,
    missile_range_ind       = nil,     -- Kept ONLY to restore it!

    -- Readback Diagnostics
    rb_valid                = false,
    rb_name                 = "None",
    rb_pos_x                = 0.0,
    rb_pos_y                = 0.0,
    rb_scale                = 0.0,
    rb_vis                  = -1,
    rb_vis_str              = "None",
    rb_match                = false,

    -- Metrics
    tick_counter            = 0,
    restored_missile_ind    = false,
}

-- -----------------------------------------------------------------------------
-- RESTORE MissileRangeIndicator TO ORIGINAL DEFAULTS
-- -----------------------------------------------------------------------------
local function restore_missile_indicator()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return false end

    local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
    local restored = 0

    for _, w in ipairs(all_w) do
        local fn = get_safe_name(w)
        if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
            local sn = get_short_name(w)
            if sn == "MissileRangeIndicator" and fn:find("MainFlight", 1, true) then
                pcall(function()
                    -- Restore original UMG transforms
                    w:call("SetRenderTranslation", { X = 0.0, Y = 0.0 })
                    w:call("SetRenderScale", { X = 1.0, Y = 1.0 })
                    w:call("SetRenderTransformAngle", 0.0)
                    w:call("SetRenderOpacity", 1.0)
                    w:call("SetVisibility", 3) -- 3 = HitTestInvisible (original game state)

                    -- Restore original slot size
                    local slot = safe_call(function() return w.Slot end, nil)
                    if slot and is_valid(slot) then
                        pcall(function() slot:call("SetSize", { X = 30.0, Y = 20.0 }) end)
                    end
                end)
                restored = restored + 1
            end
        end
    end

    S.restored_missile_ind = (restored > 0)
    return restored > 0
end

-- -----------------------------------------------------------------------------
-- Discovery: Scan Target Locator Widgets
-- -----------------------------------------------------------------------------
local function scan_locator_widgets()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return false end

    local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}

    for _, w in ipairs(all_w) do
        local fn = get_safe_name(w)
        if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
            local sn = get_short_name(w)

            -- 1. Locator_Wingman (Official arrow image widget with T_HUD_LocatorEscort_000)
            if sn == "Locator_Wingman" then
                S.wingman_img = w
                local p = safe_call(function() return w:call("GetParent") end, nil)
                if p and is_valid(p) then S.wingman_parent = p end
            elseif fn:find("WBP_HUD_Locator_Wingman", 1, true) and sn:find("WBP_HUD_Locator_Wingman", 1, true) then
                S.wingman_parent = w

            -- 2. WBP_LocatorWidget (Official C++ Slate Locator Widget)
            elseif (sn == "WBP_LocatorWidget" or fn:find("Parts_Locator", 1, true)) and fn:find("MainFlight", 1, true) then
                S.wbp_locator = w
            elseif sn == "DynamicDrawCanvas" and fn:find("MainFlight", 1, true) then
                S.wbp_locator_parent = w
            elseif sn == "WorldToScreenDrawCanvas" and fn:find("MainFlight", 1, true) then
                S.wbp_world_canvas = w
            end
        end
    end

    -- Run restoration on every scan to guarantee MissileRangeIndicator stays normal
    restore_missile_indicator()
    return true
end

-- -----------------------------------------------------------------------------
-- Telemetry & Accurate Vector Math (Safe atan2)
-- -----------------------------------------------------------------------------
local function update_telemetry()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.pawn = pawn
    if not pawn or not is_valid(pawn) then return end

    -- Fetch Locked Target
    local tgt = nil
    local ts_comp = safe_call(function() return pawn.TargetSelection end, nil)
    if ts_comp and ts_comp.SelectedTarget then tgt = ts_comp.SelectedTarget end
    if not tgt then
        local fc = safe_call(function() return pawn.FocusTargetComponent end, nil)
        if fc and fc.FocusTarget then tgt = fc.FocusTarget end
    end

    S.target_actor = tgt
    if not tgt or not is_valid(tgt) then
        S.target_name = "None"
        S.target_dist_m = 0
        S.is_offscreen = false
        return
    end

    S.target_name = get_short_name(tgt)

    -- World Locations
    local p_loc = safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
    local t_loc = safe_call(function() return tgt:call("K2_GetActorLocation") end, nil)
    local p_rot = safe_call(function() return pawn:call("K2_GetActorRotation") end, nil)

    if not (p_loc and t_loc and p_rot) then return end

    local dx = (t_loc.X or t_loc.x or 0) - (p_loc.X or p_loc.x or 0)
    local dy = (t_loc.Y or t_loc.y or 0) - (p_loc.Y or p_loc.y or 0)
    local dz = (t_loc.Z or t_loc.z or 0) - (p_loc.Z or p_loc.z or 0)
    local dist_cm = math.sqrt(dx * dx + dy * dy + dz * dz)
    S.target_dist_m = math.floor(dist_cm / 100.0)

    if dist_cm < 1.0 then return end

    local ndx, ndy, ndz = dx / dist_cm, dy / dist_cm, dz / dist_cm

    local pitch = math.rad(p_rot.Pitch or p_rot.pitch or 0)
    local yaw   = math.rad(p_rot.Yaw or p_rot.yaw or 0)
    local roll  = math.rad(p_rot.Roll or p_rot.roll or 0)

    -- Body frame rotation: Forward=+X, Right=+Y, Up=+Z
    local cos_y, sin_y = math.cos(-yaw), math.sin(-yaw)
    local x1 = ndx * cos_y - ndy * sin_y
    local y1 = ndx * sin_y + ndy * cos_y
    local z1 = ndz

    local cos_p, sin_p = math.cos(-pitch), math.sin(-pitch)
    local x2 = x1 * cos_p + z1 * sin_p
    local y2 = y1
    local z2 = -x1 * sin_p + z1 * cos_p

    local cos_r, sin_r = math.cos(-roll), math.sin(-roll)
    local lx = x2
    local ly = y2 * cos_r - z2 * sin_r
    local lz = y2 * sin_r + z2 * cos_r

    -- Horizontal Azimuth
    local az_rad = safe_atan2(ly, math.max(0.001, lx))
    local az_deg = math.deg(az_rad)
    if lx < 0 then
        if ly >= 0 then az_deg = 180.0 - az_deg else az_deg = -180.0 - az_deg end
    end
    S.azimuth_deg = az_deg

    -- Vertical Elevation
    local el_rad = safe_atan2(lz, math.max(0.001, lx))
    S.elevation_deg = math.deg(el_rad)

    local boresight_angle = math.sqrt(az_deg * az_deg + S.elevation_deg * S.elevation_deg)
    S.is_offscreen = (boresight_angle > S.offscreen_threshold_deg) or (lx < 0)

    -- ACCURATE SCREEN BEARING ANGLE (HUD Plane Projection)
    -- X_hud = Right (+ly), Y_hud = Down (-lz)
    -- Bearing: 0 = Right, -90 = Up (North), 180/-180 = Left (West), +90 = Down (South)
    local screen_bearing_rad = safe_atan2(-lz, ly)
    S.screen_bearing_deg = math.deg(screen_bearing_rad)

    -- Computed arrow heading (rotation angle in degrees)
    S.arrow_heading_deg = S.screen_bearing_deg + S.texture_base_heading + S.angle_fine_tune
end

-- -----------------------------------------------------------------------------
-- Apply 2D Widget to Cockpit HUD Ring
-- -----------------------------------------------------------------------------
local function apply_widget_to_hud_ring(w, parent)
    if not w or not is_valid(w) then return false end

    -- Position on HUD Ring
    local bearing_rad = math.rad(S.screen_bearing_deg)
    local pos_x = S.center_x + math.cos(bearing_rad) * S.ring_radius
    local pos_y = S.center_y + math.sin(bearing_rad) * S.ring_radius

    pcall(function()
        -- Ensure Ancestors are visible
        if S.wbp_world_canvas and is_valid(S.wbp_world_canvas) then
            S.wbp_world_canvas:call("SetVisibility", 4)
            S.wbp_world_canvas:call("SetRenderOpacity", 1.0)
        end
        if parent and is_valid(parent) then
            parent:call("SetVisibility", 4)
            parent:call("SetRenderOpacity", 1.0)
        end

        -- Widget itself
        w:call("SetVisibility", 0) -- 0 = Visible
        w:call("SetRenderOpacity", S.opacity)

        local slot = safe_call(function() return w.Slot end, nil)
        if slot and is_valid(slot) then
            pcall(function() slot:call("SetSize", { X = S.slot_w, Y = S.slot_h }) end)
        end

        w:call("SetRenderTransformAngle", S.arrow_heading_deg)
        w:call("SetRenderTranslation", { X = pos_x, Y = pos_y })
        w:call("SetRenderScale", { X = S.scale, Y = S.scale })
    end)

    -- Live Readback
    local ok_rt, rt = pcall(function() return w:get_property("RenderTransform") end)
    if ok_rt and rt ~= nil then
        local tr = safe_call(function() return rt.Translation end, nil)
        S.rb_pos_x = tr and (tr.X or tr.x or 0) or 0
        S.rb_pos_y = tr and (tr.Y or tr.y or 0) or 0
        local sc = safe_call(function() return rt.Scale end, nil)
        S.rb_scale = sc and (sc.X or sc.x or 0) or 0
        S.rb_match = (math.abs(S.rb_pos_x - pos_x) < 2.0 and math.abs(S.rb_pos_y - pos_y) < 2.0)
    end

    local ok_v, v = pcall(function() return w:call("GetVisibility") end)
    if ok_v and type(v) == "number" then
        S.rb_vis = v
        local vis_names = { [0]="Visible", [1]="Collapsed", [2]="Hidden", [3]="HitTestInvisible", [4]="SelfHitTestInvisible" }
        S.rb_vis_str = vis_names[v] or tostring(v)
    end

    return true
end

-- -----------------------------------------------------------------------------
-- Main Engine Tick
-- -----------------------------------------------------------------------------
local function on_tick()
    S.tick_counter = S.tick_counter + 1

    -- Periodic discovery
    if S.tick_counter % 300 == 0 or not S.wingman_img then
        scan_locator_widgets()
    end

    update_telemetry()

    local should_show = S.enabled and (S.is_offscreen or S.force_test_display)

    if should_show then
        if S.target_mode == 1 then
            -- Target 1: Locator_Wingman (Official native arrow image widget)
            S.rb_name = "Locator_Wingman (Arrow Image)"
            local ok = apply_widget_to_hud_ring(S.wingman_img, S.wingman_parent)
            S.rb_valid = ok
        elseif S.target_mode == 2 then
            -- Target 2: WBP_LocatorWidget (Official C++ Slate locator widget)
            S.rb_name = "WBP_LocatorWidget (Slate)"
            local ok = apply_widget_to_hud_ring(S.wbp_locator, S.wbp_locator_parent)
            S.rb_valid = ok
        end
    else
        -- Hide when on-screen
        if S.wingman_img and is_valid(S.wingman_img) then
            pcall(function() S.wingman_img:call("SetVisibility", 2) end)
        end
    end
end

if uevr.sdk.callbacks.on_post_engine_tick ~= nil then
    uevr.sdk.callbacks.on_post_engine_tick(function()
        safe_call(on_tick)
    end)
end

-- -----------------------------------------------------------------------------
-- UI Helpers
-- -----------------------------------------------------------------------------
local function safe_same_line()
    if imgui and imgui.same_line then imgui.same_line() end
end

local function render_slider(label, current_val, min_v, max_v, step, id)
    local changed = false
    local cur = current_val

    if imgui.button(" - ##dec_" .. id) then
        cur = math.max(min_v, cur - step)
        changed = true
    end
    safe_same_line()

    if imgui.button(" + ##inc_" .. id) then
        cur = math.min(max_v, cur + step)
        changed = true
    end
    safe_same_line()

    imgui.text(string.format(" %s: %.1f", label, cur))
    return changed, cur
end

-- -----------------------------------------------------------------------------
-- Script UI (ImGui) - Zero-Scroll Dashboard
-- -----------------------------------------------------------------------------
local function render_ui()
    imgui.text_colored("======================================================================", 0xFF00FFCC)
    imgui.text_colored("  AC8 NATIVE HUD TARGET LOCATOR (v16 ZERO-SCROLL)", 0xFF00FFCC)
    imgui.text_colored("======================================================================", 0xFF00FFCC)

    -- Row 1: 1-Click Target Selector Buttons
    local m = S.target_mode
    if imgui.button(string.format("%s [1: Locator_Wingman (Arrow Image)]##m1", (m==1 and "[*]" or "[ ]"))) then
        S.target_mode = 1
    end
    safe_same_line()
    if imgui.button(string.format("%s [2: WBP_LocatorWidget (Slate)]##m2", (m==2 and "[*]" or "[ ]"))) then
        S.target_mode = 2
    end

    -- Row 2: Master Controls & Emergency Restoration
    local ch_en, val_en = imgui.checkbox("Active##chk_en", S.enabled)
    if ch_en then S.enabled = val_en end
    safe_same_line()

    local ch_ft, val_ft = imgui.checkbox("Force Test Display##chk_ft", S.force_test_display)
    if ch_ft then S.force_test_display = val_ft end
    safe_same_line()

    if imgui.button("Restore MissileIndicator##btn_rest") then
        restore_missile_indicator()
    end
    safe_same_line()

    if imgui.button("Rescan Widgets##btn_rescan") then
        scan_locator_widgets()
    end

    imgui.separator()

    -- Row 3: Target Telemetry & Angle Vector
    imgui.text_colored(string.format("LOCKED TARGET: %s  |  Distance: %dm  |  Off-screen: %s",
        S.target_name, S.target_dist_m, S.is_offscreen and "YES" or "NO"), 0xFFFFAA00)
    imgui.text(string.format("  Azimuth: %+.1f deg (H) | Elevation: %+.1f deg (V) | Bearing: %+.1f deg",
        S.azimuth_deg, S.elevation_deg, S.screen_bearing_deg))

    -- Row 4: Live Memory Readback & Status
    if S.rb_valid then
        local match_col = S.rb_match and 0xFF00FF00 or 0xFFFF5555
        local match_txt = S.rb_match and "[OK: MATCH - GAME ACCEPTED VALUES]" or "[OVERRIDDEN!]"
        imgui.text_colored(string.format("ACTIVE: %s  |  Handle: FOUND", S.rb_name), 0xFF00FF00)
        imgui.text(string.format("  Pos: (%.1f, %.1f) | Scale: %.2f | Vis: %s | Status: ",
            S.rb_pos_x, S.rb_pos_y, S.rb_scale, S.rb_vis_str))
        safe_same_line()
        imgui.text_colored(match_txt, match_col)
    else
        imgui.text_colored(string.format("ACTIVE: %s  |  Handle: SEARCHING...", S.rb_name), 0xFFFF4444)
    end

    -- Row 5: Quick Presets
    if imgui.button("[Preset: Center (690, 756)]##btn_p1") then
        S.center_x = 690.0
        S.center_y = 756.0
        S.ring_radius = 0.0
        S.scale = 1.5
    end
    safe_same_line()
    if imgui.button("[Preset: HUD Ring (Rad=220)]##btn_p2") then
        S.center_x = 690.0
        S.center_y = 756.0
        S.ring_radius = 220.0
        S.scale = 1.5
    end
    safe_same_line()
    if imgui.button("[Preset: Giant 2.5x]##btn_p3") then
        S.scale = 2.5
        S.slot_w = 400.0
        S.slot_h = 400.0
    end

    imgui.separator()

    -- Advanced Tuning (Collapsing header, default closed)
    if imgui.collapsing_header and imgui.collapsing_header("Advanced Tuning & Angle Calibration##head_adv") then
        local ch_cx, val_cx = render_slider("Center X", S.center_x, -500.0, 2000.0, 10.0, "cx")
        if ch_cx then S.center_x = val_cx end

        local ch_cy, val_cy = render_slider("Center Y", S.center_y, -500.0, 2000.0, 10.0, "cy")
        if ch_cy then S.center_y = val_cy end

        local ch_rad, val_rad = render_slider("Ring Radius", S.ring_radius, 0.0, 500.0, 10.0, "rad")
        if ch_rad then S.ring_radius = val_rad end

        local ch_sc, val_sc = render_slider("Render Scale", S.scale, 0.2, 5.0, 0.2, "sc")
        if ch_sc then S.scale = val_sc end

        local ch_tbh, val_tbh = render_slider("Base Heading (deg)", S.texture_base_heading, -180.0, 180.0, 45.0, "tbh")
        if ch_tbh then S.texture_base_heading = val_tbh end

        local ch_at, val_at = render_slider("Fine Angle Tune (deg)", S.angle_fine_tune, -180.0, 180.0, 5.0, "at")
        if ch_at then S.angle_fine_tune = val_at end
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

-- Immediately restore MissileRangeIndicator on script load
restore_missile_indicator()

print(string.format("[%s] Loaded successfully (%s).", SCRIPT_NAME, SCRIPT_VER))
