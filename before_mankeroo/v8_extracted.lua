--[[
  ============================================================================
  ac8_target_locator_test.lua : Target Off-Screen Arrow Restoration Test (v8)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Design:     Based on the proven Pitch/Yaw Artificial Horizon Solution!
              - Uses native UMG Image widgets present in MainFlight HUD
              - Awakes parent panels (LandingGuide / MissileRangePanel)
              - Injects official HUD arrow textures (T_HUD_UIArrow_001, etc.)
              - Dynamically positions & rotates on the HUD ring when locked
                target maneuvers outside cockpit boresight
              - Full interactive Sliders, Modes, Texture Swaps, and Force-Show!

  Safety:     100% Pure ASCII, Game-Thread Only (on_post_engine_tick), Crash-Safe
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Locator-Test"
local SCRIPT_VER  = "v8-HorizonArchitecture"

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

-- -----------------------------------------------------------------------------
-- Texture Presets (Official AC8 HUD Textures)
-- -----------------------------------------------------------------------------
local TEX_PRESETS = {
    [0] = {
        name = "T_HUD_UIArrow_001 (Official HUD Triangle Arrow)",
        path = "Texture2D /Game/UI/Texture/HUD/T_HUD_UIArrow_001.T_HUD_UIArrow_001",
    },
    [1] = {
        name = "T_HUD_Multi_TargetPin_002 (Official 3D Target Pin)",
        path = "Texture2D /Game/UI/Texture/HUD/Container/T_HUD_Multi_TargetPin_002.T_HUD_Multi_TargetPin_002",
    },
    [2] = {
        name = "T_HUD_LocatorEscort_000 (Official Locator Escort Arrow)",
        path = "Texture2D /Game/UI/Texture/HUD/T_HUD_LocatorEscort_000.T_HUD_LocatorEscort_000",
    },
    [3] = {
        name = "T_HUD_UIArrow_Line_002 (Official Fine Line Arrow)",
        path = "Texture2D /Game/UI/Texture/HUD/T_HUD_UIArrow_Line_002.T_HUD_UIArrow_Line_002",
    },
    [4] = {
        name = "T_HUD_LandingGuideVertical_000 (Native Guide Needle)",
        path = "Texture2D /Game/UI/Texture/HUD/T_HUD_LandingGuideVertical_000.T_HUD_LandingGuideVertical_000",
    },
}

-- -----------------------------------------------------------------------------
-- State & Configuration Table
-- -----------------------------------------------------------------------------
local S = {
    enabled                 = false,
    force_test_display      = false,   -- Bypass off-screen check: Always display arrow for tuning

    -- Modes:
    -- 0: MissileRangeIndicator (Native Arrow Image in Altimeter / PitchLadder area)
    -- 1: LandingGuideVertical (Native Guide Image in MainCanvas, Horizon-proven)
    -- 2: LandingGuideHorizontal (Native Horizon Image in MainCanvas)
    -- 3: Locator_Wingman (Native WBP_HUD_Locator_Wingman Image)
    mode                    = 0,
    tex_preset_idx          = 0,

    -- Geometry & Placement (Pixels relative to HUD Center / PitchLadder)
    ring_radius             = 320.0,
    scale_x                 = 2.0,
    scale_y                 = 2.0,
    opacity                 = 1.0,
    center_offset_x         = 0.0,
    center_offset_y         = 0.0,

    -- Angle & Tracking
    angle_threshold         = 22.0,    -- Boresight cutoff angle (deg)
    angle_fine_tune         = 0.0,     -- Manual angle offset (deg)
    invert_rotation         = false,
    blink                   = false,

    -- Color Tint
    color_r                 = 0.0,
    color_g                 = 1.0,
    color_b                 = 0.2,
    color_a                 = 1.0,

    -- Runtime Telemetry
    pawn                    = nil,
    target_actor            = nil,
    target_name             = "None",
    target_dist_m           = 0,
    azimuth_deg             = 0.0,
    elevation_deg           = 0.0,
    is_offscreen            = false,
    arrow_heading_deg       = 0.0,

    -- Discovered Native Widget Handles
    missile_range_ind       = nil,
    missile_range_panel     = nil,
    landing_guide_vert      = nil,
    landing_guide_horiz     = nil,
    landing_guide_parent    = nil,
    locator_wingman_img     = nil,
    locator_wingman_parent  = nil,

    cached                  = false,
    last_pawn_ptr           = nil,
    last_applied_tex        = -1,
    status_msg              = "Idle (Disabled).",
}

-- -----------------------------------------------------------------------------
-- Texture Resolution Helper
-- -----------------------------------------------------------------------------
local function find_texture_object(preset_idx)
    local preset = TEX_PRESETS[preset_idx]
    if not preset then return nil end

    local obj = api:find_uobject(preset.path)
    if obj then return obj end

    local tex_class = api:find_uobject("Class /Script/Engine.Texture2D")
    if tex_class then
        local all_t = safe_call(function() return tex_class:get_objects_matching(false) end, {}) or {}
        local needle = preset.path:match("([^.]+)$")
        for _, t in ipairs(all_t) do
            local fn = get_safe_name(t)
            if fn:find(needle, 1, true) then return t end
        end
    end
    return nil
end

local function apply_brush_texture(widget, tex_obj)
    if not widget or not tex_obj then return false end
    local ok1 = pcall(function()
        widget:call("SetBrushFromTexture", tex_obj, false)
    end)
    if ok1 then return true end

    local ok2 = pcall(function()
        local b = widget.Brush
        if b then
            b.ResourceObject = tex_obj
            widget:call("SetBrush", b)
        end
    end)
    return ok2
end

-- -----------------------------------------------------------------------------
-- HUD Widget Discovery (Finds MainFlight Native Images)
-- -----------------------------------------------------------------------------
local function reset_cache()
    S.missile_range_ind      = nil
    S.missile_range_panel    = nil
    S.landing_guide_vert     = nil
    S.landing_guide_horiz    = nil
    S.landing_guide_parent   = nil
    S.locator_wingman_img    = nil
    S.locator_wingman_parent = nil
    S.cached                 = false
    S.last_pawn_ptr          = nil
    S.last_applied_tex       = -1
end

local function find_hud_elements()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return false end

    local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}

    for _, w in ipairs(all_w) do
        local fn = get_safe_name(w)
        if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
            local sn = get_short_name(w)

            -- 1. MissileRangeIndicator (Child of MissileRangePanel -> Altimeter in MainFlight)
            if sn == "MissileRangeIndicator" and fn:find("MainFlight", 1, true) then
                S.missile_range_ind = w
            elseif sn == "MissileRangePanel" and fn:find("MainFlight", 1, true) then
                S.missile_range_panel = w

            -- 2. LandingGuide (Child of MainCanvas in MainFlight)
            elseif sn == "LandingGuide" and fn:find("MainFlight", 1, true) then
                S.landing_guide_parent = w
            elseif sn == "LandingGuideVertical" and fn:find("MainFlight", 1, true) then
                S.landing_guide_vert = w
            elseif sn == "LandingGuideHorizontal" and fn:find("MainFlight", 1, true) then
                S.landing_guide_horiz = w

            -- 3. Locator_Wingman (Native Escort Locator)
            elseif sn == "Locator_Wingman" then
                if not S.locator_wingman_img then S.locator_wingman_img = w end
            elseif fn:find("WBP_HUD_Locator_Wingman", 1, true) and sn:find("WBP_HUD_Locator_Wingman", 1, true) then
                if not S.locator_wingman_parent then S.locator_wingman_parent = w end
            end
        end
    end

    if S.missile_range_ind or S.landing_guide_vert or S.landing_guide_horiz or S.locator_wingman_img then
        S.cached = true
        return true
    end
    return false
end

-- -----------------------------------------------------------------------------
-- 3D Target Acquisition & Orientation Vector Math
-- -----------------------------------------------------------------------------
local function update_target_orientation()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.pawn = pawn
    if not pawn or not is_valid(pawn) then return end

    -- 1. Identify Target
    local tgt = nil
    local ts_comp = safe_call(function() return pawn.TargetSelection end, nil)
    if ts_comp and ts_comp.SelectedTarget then
        tgt = ts_comp.SelectedTarget
    end
    if not tgt then
        local focus_comp = safe_call(function() return pawn.FocusTargetComponent end, nil)
        if focus_comp and focus_comp.FocusTarget then
            tgt = focus_comp.FocusTarget
        end
    end

    -- Fallback: Look for active ChronicleTargetContainerActor in sky
    if not tgt then
        local actor_class = api:find_uobject("Class /Script/Engine.Actor")
        if actor_class then
            local all_acts = safe_call(function() return actor_class:get_objects_matching(false) end, {}) or {}
            local nearest_dist = 9999999.0
            local p_loc = safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
            for _, a in ipairs(all_acts) do
                local fn = get_safe_name(a)
                if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
                    local a_loc = safe_call(function() return a:call("K2_GetActorLocation") end, nil)
                    if p_loc and a_loc then
                        local dx = (a_loc.X or a_loc.x or 0) - (p_loc.X or p_loc.x or 0)
                        local dy = (a_loc.Y or a_loc.y or 0) - (p_loc.Y or p_loc.y or 0)
                        local dz = (a_loc.Z or a_loc.z or 0) - (p_loc.Z or p_loc.z or 0)
                        local d = dx * dx + dy * dy + dz * dz
                        if d < nearest_dist then
                            nearest_dist = d
                            tgt = a
                        end
                    end
                end
            end
        end
    end

    S.target_actor = tgt
    if not tgt then
        S.target_name = "None"
        S.target_dist_m = 0
        S.is_offscreen = false
        return
    end

    S.target_name = get_short_name(tgt)

    -- 2. 3D Vector Math from Player Pawn
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

    -- Normalize
    local ndx, ndy, ndz = dx / dist_cm, dy / dist_cm, dz / dist_cm

    -- Aircraft Rotation (Pitch, Yaw, Roll)
    local pitch = math.rad(p_rot.Pitch or p_rot.pitch or 0)
    local yaw   = math.rad(p_rot.Yaw or p_rot.yaw or 0)
    local roll  = math.rad(p_rot.Roll or p_rot.roll or 0)

    -- Rotate into Local Aircraft Space
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

    -- Angles from Boresight (Forward)
    local az_deg = math.deg(math.atan(ly, math.max(0.001, lx)))
    local el_deg = math.deg(math.atan(lz, math.max(0.001, lx)))
    if lx < 0 then
        if ly >= 0 then az_deg = 180.0 - az_deg else az_deg = -180.0 - az_deg end
    end
    S.azimuth_deg = az_deg
    S.elevation_deg = el_deg

    -- Off-screen Condition: Boresight angle exceeds threshold OR target is behind aircraft
    local boresight_angle = math.sqrt(az_deg * az_deg + el_deg * el_deg)
    S.is_offscreen = (boresight_angle > S.angle_threshold) or (lx < 0)

    -- 2D Clockwise Heading on HUD (0 deg = 12 o'clock / Up, 90 deg = 3 o'clock / Right)
    local heading_rad = math.atan(ly, lz)
    local heading_deg = math.deg(heading_rad)
    if S.invert_rotation then heading_deg = -heading_deg end
    S.arrow_heading_deg = heading_deg + S.angle_fine_tune
end

-- -----------------------------------------------------------------------------
-- HUD Widget Control & Placement
-- -----------------------------------------------------------------------------
local function apply_widget_transform(w, angle_deg, pos_x, pos_y, sx, sy, op)
    if not w or not is_valid(w) then return end
    pcall(function()
        w:call("SetVisibility", 0) -- 0 = Visible
        w:call("SetRenderOpacity", op)
        w:call("SetColorAndOpacity", { R = S.color_r, G = S.color_g, B = S.color_b, A = S.color_a })
        w:call("SetRenderTransformAngle", angle_deg)
        w:call("SetRenderTranslation", { X = pos_x, Y = pos_y })
        w:call("SetRenderScale", { X = sx, Y = sy })
    end)
end

local function hide_widget(w)
    if not w or not is_valid(w) then return end
    pcall(function()
        w:call("SetVisibility", 2) -- 2 = Hidden
        w:call("SetRenderOpacity", 0.0)
    end)
end

-- -----------------------------------------------------------------------------
-- Main Enforcement Tick Loop
-- -----------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    if not S.enabled then return end

    tick_count = tick_count + 1

    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    if not pawn then
        if S.cached then reset_cache() end
        return
    end

    if S.last_pawn_ptr ~= pawn then
        reset_cache()
        S.last_pawn_ptr = pawn
    end

    -- Discover Widgets
    if not S.cached then
        find_hud_elements()
    end

    -- Texture Injection (when changed)
    if S.last_applied_tex ~= S.tex_preset_idx then
        local tex_obj = find_texture_object(S.tex_preset_idx)
        if tex_obj then
            if S.landing_guide_vert then apply_brush_texture(S.landing_guide_vert, tex_obj) end
            if S.landing_guide_horiz then apply_brush_texture(S.landing_guide_horiz, tex_obj) end
            if S.missile_range_ind then apply_brush_texture(S.missile_range_ind, tex_obj) end
            if S.locator_wingman_img then apply_brush_texture(S.locator_wingman_img, tex_obj) end
            S.last_applied_tex = S.tex_preset_idx
        end
    end

    -- Awaken Parent Panels
    if S.landing_guide_parent and is_valid(S.landing_guide_parent) then
        pcall(function()
            S.landing_guide_parent:call("SetVisibility", 0)
            S.landing_guide_parent:call("SetRenderOpacity", 1.0)
        end)
    end

    if S.missile_range_panel and is_valid(S.missile_range_panel) then
        pcall(function()
            S.missile_range_panel:call("SetVisibility", 0)
            S.missile_range_panel:call("SetRenderOpacity", 1.0)
        end)
    end

    if S.locator_wingman_parent and is_valid(S.locator_wingman_parent) then
        pcall(function()
            S.locator_wingman_parent:call("SetVisibility", 0)
            S.locator_wingman_parent:call("SetRenderOpacity", 1.0)
        end)
    end

    -- Update 3D Tracking
    update_target_orientation()

    -- Determine Active Display State
    local show_active = S.force_test_display or (S.is_offscreen and S.target_actor ~= nil)

    -- Blink modulation
    local final_opacity = S.opacity
    if S.blink and show_active then
        if (tick_count % 30) < 15 then final_opacity = 0.0 end
    end

    -- Active Target Widget
    local target_w = nil
    if S.mode == 0 then
        target_w = S.missile_range_ind
    elseif S.mode == 1 then
        target_w = S.landing_guide_vert
    elseif S.mode == 2 then
        target_w = S.landing_guide_horiz
    elseif S.mode == 3 then
        target_w = S.locator_wingman_img
    end

    if not show_active then
        -- Suppress
        if target_w then hide_widget(target_w) end
        return
    end

    -- Compute Polar Coordinates on HUD Ring
    local rad = math.rad(S.arrow_heading_deg)
    local target_x = S.center_offset_x + S.ring_radius * math.sin(rad)
    local target_y = S.center_offset_y - S.ring_radius * math.cos(rad)

    -- Apply transform to selected widget
    if target_w then
        apply_widget_transform(target_w, S.arrow_heading_deg, target_x, target_y, S.scale_x, S.scale_y, final_opacity)
    end
end)

-- -----------------------------------------------------------------------------
-- Interactive UI Helpers
-- -----------------------------------------------------------------------------
local HAS_SAME_LINE = false
pcall(function() HAS_SAME_LINE = (imgui ~= nil and imgui.same_line ~= nil) end)
local function safe_same_line()
    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end
end

local function render_slider(label, cur_val, min_v, max_v, step, id)
    local changed = false
    local cur = cur_val or 0.0

    if imgui.button(" - ##dec_" .. id) then
        cur = math.max(min_v, cur - step)
        changed = true
    end
    safe_same_line()

    local cs, vs = imgui.slider_float("##s_" .. id, cur, min_v, max_v)
    if cs then
        cur = vs
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
-- Script UI (ImGui)
-- -----------------------------------------------------------------------------
local function render_ui()
    imgui.text("======================================================================")
    imgui.text_colored("  AC8 TARGET LOCATOR ARROW RESTORATION (v8)", 0xFF00FFCC)
    imgui.text("======================================================================")
    imgui.text("Pitch/Yaw Horizon-proven architecture: Wakes native HUD image in VR.")
    imgui.separator()

    local ch_en, val_en = imgui.checkbox("Activate Target Locator##tloc_en", S.enabled)
    if ch_en then
        S.enabled = val_en
        if S.enabled then find_hud_elements() end
    end

    safe_same_line()
    local ch_test, val_test = imgui.checkbox("Force Test Display (Always On)##tloc_test", S.force_test_display)
    if ch_test then S.force_test_display = val_test end

    imgui.separator()

    if S.enabled then
        -- Telemetry
        imgui.text_colored("--- Targeting & Orientation Telemetry ---", 0xFF00E5FF)
        imgui.text(string.format("Locked Target: %s  |  Distance: %dm", S.target_name, S.target_dist_m))
        imgui.text(string.format("Azimuth: %+.1f deg  |  Elevation: %+.1f deg", S.azimuth_deg, S.elevation_deg))

        if S.force_test_display then
            imgui.text_colored(">>> FORCE TEST DISPLAY ACTIVE: Bypassing off-screen check <<<", 0xFFFFAA00)
        elseif S.is_offscreen then
            imgui.text_colored(string.format(">>> TARGET OFF-SCREEN: Arrow Heading %+.1f deg <<<", S.arrow_heading_deg), 0xFF0055FF)
        else
            imgui.text_colored("Target in Boresight (Arrow Hidden)", 0xFF44FF44)
        end

        imgui.separator()

        -- Mode Selection
        imgui.text_colored("1. Native HUD Element Mode (Which widget to control):", 0xFFFFAA00)
        local m0 = (S.mode == 0)
        local m1 = (S.mode == 1)
        local m2 = (S.mode == 2)
        local m3 = (S.mode == 3)
        if imgui.radio_button("Mode 0: MissileRangeIndicator (Native Arrow in Altimeter)##m0", m0) then S.mode = 0 end
        if imgui.radio_button("Mode 1: LandingGuideVertical (MainCanvas Needle, Proven)##m1", m1) then S.mode = 1 end
        if imgui.radio_button("Mode 2: LandingGuideHorizontal (MainCanvas Bar, Proven)##m2", m2) then S.mode = 2 end
        if imgui.radio_button("Mode 3: Locator_Wingman (Native Escort Locator Image)##m3", m3) then S.mode = 3 end

        imgui.separator()

        -- Texture Selection
        imgui.text_colored("2. Official Texture Swap (SetBrushFromTexture):", 0xFFFFAA00)
        for idx = 0, #TEX_PRESETS do
            local p = TEX_PRESETS[idx]
            local is_sel = (S.tex_preset_idx == idx)
            if imgui.radio_button(string.format("%s##tex_%d", p.name, idx), is_sel) then
                S.tex_preset_idx = idx
            end
        end

        imgui.separator()

        -- Sliders: Geometry & Placement
        imgui.text_colored("3. Sliders: Size, Distance & Offset (HUD Ring Space):", 0xFFFFAA00)

        local ch_rad, val_rad = render_slider("Ring Radius (px)", S.ring_radius, 50.0, 800.0, 10.0, "rad")
        if ch_rad then S.ring_radius = val_rad end

        local ch_sx, val_sx = render_slider("Arrow Length (Scale X)", S.scale_x, 0.2, 8.0, 0.2, "sx")
        if ch_sx then S.scale_x = val_sx end

        local ch_sy, val_sy = render_slider("Arrow Width (Scale Y)", S.scale_y, 0.2, 8.0, 0.2, "sy")
        if ch_sy then S.scale_y = val_sy end

        local ch_op, val_op = render_slider("Opacity", S.opacity, 0.1, 1.0, 0.05, "op")
        if ch_op then S.opacity = val_op end

        local ch_ox, val_ox = render_slider("Center Offset X", S.center_offset_x, -400.0, 400.0, 10.0, "ox")
        if ch_ox then S.center_offset_x = val_ox end

        local ch_oy, val_oy = render_slider("Center Offset Y", S.center_offset_y, -400.0, 400.0, 10.0, "oy")
        if ch_oy then S.center_offset_y = val_oy end

        local ch_th, val_th = render_slider("FOV Threshold (deg)", S.angle_threshold, 5.0, 60.0, 1.0, "th")
        if ch_th then S.angle_threshold = val_th end

        local ch_atune, val_atune = render_slider("Angle Fine-Tune (deg)", S.angle_fine_tune, -180.0, 180.0, 5.0, "atune")
        if ch_atune then S.angle_fine_tune = val_atune end

        local c_inv, v_inv = imgui.checkbox("Invert Arrow Rotation Angle##inv_rot", S.invert_rotation)
        if c_inv then S.invert_rotation = v_inv end
        safe_same_line()
        local c_blk, v_blk = imgui.checkbox("Blink (Flash) Arrow##blk", S.blink)
        if c_blk then S.blink = v_blk end

        imgui.separator()

        -- Presets
        imgui.text_colored("4. Quick Position Presets:", 0xFFFFAA00)
        if imgui.button("Whisky Mark Center (Rad: 0, Off: 0, 0)##btn_p0") then
            S.ring_radius = 0.0; S.center_offset_x = 0.0; S.center_offset_y = 0.0
        end
        safe_same_line()
        if imgui.button("Pitch Ladder Right (Rad: 200, Off: 0, 0)##btn_p1") then
            S.ring_radius = 200.0; S.center_offset_x = 0.0; S.center_offset_y = 0.0
        end
        safe_same_line()
        if imgui.button("Standard HUD Ring (Rad: 320, Off: 0, 0)##btn_p2") then
            S.ring_radius = 320.0; S.center_offset_x = 0.0; S.center_offset_y = 0.0
        end

        imgui.separator()

        -- Color
        imgui.text_colored("5. Colors:", 0xFFFFAA00)
        if imgui.button("HUD Classic Green##col_grn") then
            S.color_r = 0.0; S.color_g = 1.0; S.color_b = 0.2; S.color_a = 1.0
        end
        safe_same_line()
        if imgui.button("Alert Red##col_red") then
            S.color_r = 1.0; S.color_g = 0.1; S.color_b = 0.1; S.color_a = 1.0
        end
        safe_same_line()
        if imgui.button("Cyan Blue##col_cyn") then
            S.color_r = 0.0; S.color_g = 0.8; S.color_b = 1.0; S.color_a = 1.0
        end

        imgui.separator()

        -- Widget Status
        imgui.text_colored("--- Native Widget Binding Diagnostics ---", 0xFF888888)
        imgui.text(string.format("  MissileRangeIndicator: %s", S.missile_range_ind and "BOUND OK" or "NOT FOUND"))
        imgui.text(string.format("  LandingGuideVertical:  %s", S.landing_guide_vert and "BOUND OK" or "NOT FOUND"))
        imgui.text(string.format("  LandingGuideHorizontal:%s", S.landing_guide_horiz and "BOUND OK" or "NOT FOUND"))
        imgui.text(string.format("  Locator_Wingman:       %s", S.locator_wingman_img and "BOUND OK" or "NOT FOUND"))

        if imgui.button("Rescan Widgets Now##btn_rescan") then
            reset_cache()
            find_hud_elements()
        end
    else
        imgui.text_colored("Check [Activate Target Locator] above to start test.", 0xFF888888)
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully (%s).", SCRIPT_NAME, SCRIPT_VER))
