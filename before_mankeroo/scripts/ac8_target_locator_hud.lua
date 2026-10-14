--[[
  ============================================================================
  ac8_target_locator_hud.lua : Target Off-Screen Arrow (Locator) HUD System
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Feature:    Authentic HUD-Mounted Target Locator Arrow (Pitch Ladder Co-located)
              - Dynamically projects a guidance arrow on the HUD ring when the
                locked-on target maneuvers outside the cockpit boresight FOV
              - Co-located with the Pitch Ladder / Flight Path Marker center
              - Points directly toward the target (Azimuth & Elevation tracking)
              - Fully customizable radius, scale, angle threshold, and colors
              - Auto-saving persistent configuration (data/ac8_locator_config.txt)
  Safety:     100% Pure ASCII, Game-Thread Only (on_post_engine_tick), Crash-Safe
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Locator-HUD"

-- -----------------------------------------------------------------------------
-- 0. Safe Utilities
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 1. Configuration & Persistence (data/ac8_locator_config.txt)
-- -----------------------------------------------------------------------------
local config_file = "data/ac8_locator_config.txt"

local cfg = {
    enabled             = true,
    ring_radius         = 320.0,  -- Radius around central HUD reticle (px)
    arrow_scale_x       = 1.8,    -- Arrow length / horizontal scale
    arrow_scale_y       = 1.8,    -- Arrow width / vertical scale
    arrow_opacity       = 1.0,    -- Visibility opacity (0.0 ~ 1.0)
    center_offset_x     = 0.0,    -- Horizontal center nudge (px)
    center_offset_y     = 0.0,    -- Vertical center nudge (px)
    angle_threshold     = 22.0,   -- Off-screen threshold from boresight (deg)
    invert_rotation     = false,  -- Invert arrow direction angle
    angle_offset        = 0.0,    -- Fine-tune angle adjustment (deg)
    mode                = 0,      -- 0 = WBP_LocatorWidget, 1 = LandingGuideVertical, 2 = Dual Hybrid
    color_r             = 0.0,    -- HUD Green default: (0.0, 1.0, 0.2)
    color_g             = 1.0,
    color_b             = 0.2,
    color_a             = 1.0,
}

local function save_config()
    local f = io.open(config_file, "w")
    if not f then return end
    f:write(string.format("enabled=%s\n", tostring(cfg.enabled)))
    f:write(string.format("ring_radius=%.1f\n", cfg.ring_radius))
    f:write(string.format("arrow_scale_x=%.2f\n", cfg.arrow_scale_x))
    f:write(string.format("arrow_scale_y=%.2f\n", cfg.arrow_scale_y))
    f:write(string.format("arrow_opacity=%.2f\n", cfg.arrow_opacity))
    f:write(string.format("center_offset_x=%.1f\n", cfg.center_offset_x))
    f:write(string.format("center_offset_y=%.1f\n", cfg.center_offset_y))
    f:write(string.format("angle_threshold=%.1f\n", cfg.angle_threshold))
    f:write(string.format("invert_rotation=%s\n", tostring(cfg.invert_rotation)))
    f:write(string.format("angle_offset=%.1f\n", cfg.angle_offset))
    f:write(string.format("mode=%d\n", cfg.mode))
    f:write(string.format("color_r=%.2f\n", cfg.color_r))
    f:write(string.format("color_g=%.2f\n", cfg.color_g))
    f:write(string.format("color_b=%.2f\n", cfg.color_b))
    f:write(string.format("color_a=%.2f\n", cfg.color_a))
    f:close()
end

local function load_config()
    local f = io.open(config_file, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            if k == "enabled" then cfg.enabled = (v == "true")
            elseif k == "ring_radius" then cfg.ring_radius = tonumber(v) or cfg.ring_radius
            elseif k == "arrow_scale_x" then cfg.arrow_scale_x = tonumber(v) or cfg.arrow_scale_x
            elseif k == "arrow_scale_y" then cfg.arrow_scale_y = tonumber(v) or cfg.arrow_scale_y
            elseif k == "arrow_opacity" then cfg.arrow_opacity = tonumber(v) or cfg.arrow_opacity
            elseif k == "center_offset_x" then cfg.center_offset_x = tonumber(v) or cfg.center_offset_x
            elseif k == "center_offset_y" then cfg.center_offset_y = tonumber(v) or cfg.center_offset_y
            elseif k == "angle_threshold" then cfg.angle_threshold = tonumber(v) or cfg.angle_threshold
            elseif k == "invert_rotation" then cfg.invert_rotation = (v == "true")
            elseif k == "angle_offset" then cfg.angle_offset = tonumber(v) or cfg.angle_offset
            elseif k == "mode" then cfg.mode = tonumber(v) or cfg.mode
            elseif k == "color_r" then cfg.color_r = tonumber(v) or cfg.color_r
            elseif k == "color_g" then cfg.color_g = tonumber(v) or cfg.color_g
            elseif k == "color_b" then cfg.color_b = tonumber(v) or cfg.color_b
            elseif k == "color_a" then cfg.color_a = tonumber(v) or cfg.color_a
            end
        end
    end
    f:close()
end
pcall(load_config)

-- -----------------------------------------------------------------------------
-- 2. State & Caches
-- -----------------------------------------------------------------------------
local S = {
    pawn                = nil,
    target_actor        = nil,
    target_name         = "None",
    target_dist_m       = 0,
    azimuth_deg         = 0.0,
    elevation_deg       = 0.0,
    is_offscreen        = false,
    arrow_heading_deg   = 0.0,

    -- Widget Handles
    locator_widget      = nil,
    landing_guide_bar   = nil,
    cached              = false,
    last_pawn_ptr       = nil,
}

local function reset_cache()
    S.locator_widget    = nil
    S.landing_guide_bar = nil
    S.cached            = false
    S.last_pawn_ptr     = nil
end

-- -----------------------------------------------------------------------------
-- 3. HUD Element Discovery
-- -----------------------------------------------------------------------------
local function find_hud_widgets()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return false end

    local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {})
    for _, w in ipairs(all_w) do
        local fn = get_safe_name(w)
        if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
            if fn:find("MainFlight", 1, true) then
                local sn = get_short_name(w)
                if sn == "WBP_LocatorWidget" or fn:find("Parts_Locator", 1, true) then
                    S.locator_widget = w
                elseif sn == "LandingGuideVertical" or sn == "LandingGuideHorizontal" then
                    if not S.landing_guide_bar then
                        S.landing_guide_bar = w
                    end
                end
            end
        end
    end

    if S.locator_widget or S.landing_guide_bar then
        S.cached = true
        return true
    end
    return false
end

-- -----------------------------------------------------------------------------
-- 4. Target Acquisition & 3D Vector Math
-- -----------------------------------------------------------------------------
local function update_target_orientation()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.pawn = pawn
    if not pawn then return end

    -- 1. Acquire current locked target
    local tgt = nil
    local ts_comp = safe_call(function() return pawn.TargetSelection end, nil)
    if ts_comp then
        tgt = safe_call(function() return ts_comp.SelectedTarget end, nil)
    end
    if not tgt then
        local focus_comp = safe_call(function() return pawn.FocusTargetComponent end, nil)
        if focus_comp then
            tgt = safe_call(function() return focus_comp.FocusTarget end, nil)
        end
    end

    -- Fallback: Look for active ChronicleTargetContainerActor in sky
    if not tgt then
        local actor_class = api:find_uobject("Class /Script/Engine.Actor")
        if actor_class then
            local all_acts = safe_call(function() return actor_class:get_objects_matching(false) end, {})
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

    -- 2. Compute 3D Relative Orientation
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

    -- Normalize World Vector
    local ndx, ndy, ndz = dx / dist_cm, dy / dist_cm, dz / dist_cm

    -- Aircraft Rotation (Pitch, Yaw, Roll)
    local pitch = math.rad(p_rot.Pitch or p_rot.pitch or 0)
    local yaw   = math.rad(p_rot.Yaw or p_rot.yaw or 0)
    local roll  = math.rad(p_rot.Roll or p_rot.roll or 0)

    -- Transform into Aircraft Local Space (Forward: X, Right: Y, Up: Z)
    -- Yaw (Z-axis)
    local cos_y, sin_y = math.cos(-yaw), math.sin(-yaw)
    local x1 = ndx * cos_y - ndy * sin_y
    local y1 = ndx * sin_y + ndy * cos_y
    local z1 = ndz

    -- Pitch (Y-axis)
    local cos_p, sin_p = math.cos(-pitch), math.sin(-pitch)
    local x2 = x1 * cos_p + z1 * sin_p
    local y2 = y1
    local z2 = -x1 * sin_p + z1 * cos_p

    -- Roll (X-axis)
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
    S.is_offscreen = (boresight_angle > cfg.angle_threshold) or (lx < 0)

    -- 2D Clockwise Heading on HUD (0 deg = 12 o'clock / Up, 90 deg = 3 o'clock / Right)
    -- On HUD display: Right is +ly, Up is +lz. Screen Y is downward.
    local heading_rad = math.atan(ly, lz)
    local heading_deg = math.deg(heading_rad)
    if cfg.invert_rotation then heading_deg = -heading_deg end
    S.arrow_heading_deg = heading_deg + cfg.angle_offset
end

-- -----------------------------------------------------------------------------
-- 5. Real-Time HUD Rendering & Transform Update
-- -----------------------------------------------------------------------------
local function apply_arrow_transform(w, angle_deg, pos_x, pos_y, scale_x, scale_y)
    if not w then return end
    pcall(function()
        w:call("SetVisibility", 0) -- 0 = Visible
        w:call("SetRenderOpacity", cfg.arrow_opacity)
        w:call("SetColorAndOpacity", { R = cfg.color_r, G = cfg.color_g, B = cfg.color_b, A = cfg.color_a })
        w:call("SetRenderTransformAngle", angle_deg)
        w:call("SetRenderTranslation", { X = pos_x, Y = pos_y })
        w:call("SetRenderScale", { X = scale_x, Y = scale_y })
    end)
end

local function hide_arrow(w)
    if not w then return end
    pcall(function()
        w:call("SetVisibility", 2) -- 2 = Hidden
        w:call("SetRenderOpacity", 0.0)
    end)
end

-- Main Tick Loop
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    if not cfg.enabled then return end

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

    -- Scene Reset Detection
    if S.last_pawn_ptr ~= pawn then
        reset_cache()
        S.last_pawn_ptr = pawn
    end

    -- Pause & Cutscene Guard
    local pc = api:get_player_controller(0)
    if pc then
        local is_paused = safe_call(function() return pc:call("IsPaused") end, false)
        if is_paused then
            hide_arrow(S.locator_widget)
            hide_arrow(S.landing_guide_bar)
            return
        end
    end

    -- Cache Discovery
    if not S.cached then
        if not find_hud_widgets() then return end
    end

    -- Update Orientation Vector
    update_target_orientation()

    -- Check Off-Screen State
    if not S.is_offscreen or not S.target_actor then
        -- Target is inside boresight: Hide guidance arrow
        hide_arrow(S.locator_widget)
        hide_arrow(S.landing_guide_bar)
        return
    end

    -- Compute Polar Position on Central HUD Circle (Pitch Ladder Co-located)
    -- Radian angle: 0 deg = Up (lz), 90 deg = Right (ly)
    local rad = math.rad(S.arrow_heading_deg)
    local sin_a = math.sin(rad)
    local cos_a = math.cos(rad)

    -- In HUD Screen Space: X = Center + R * sin(angle), Y = Center - R * cos(angle)
    local target_x = cfg.center_offset_x + cfg.ring_radius * sin_a
    local target_y = cfg.center_offset_y - cfg.ring_radius * cos_a

    -- Render based on selected Mode
    if cfg.mode == 0 or cfg.mode == 2 then
        -- Mode 0 / 2: WBP_LocatorWidget
        if S.locator_widget then
            apply_arrow_transform(S.locator_widget, S.arrow_heading_deg, target_x, target_y, cfg.arrow_scale_x, cfg.arrow_scale_y)
        end
    end

    if cfg.mode == 1 or cfg.mode == 2 then
        -- Mode 1 / 2: LandingGuideVertical
        if S.landing_guide_bar then
            apply_arrow_transform(S.landing_guide_bar, S.arrow_heading_deg, target_x, target_y, cfg.arrow_scale_x, cfg.arrow_scale_y)
        end
    end
end)

-- -----------------------------------------------------------------------------
-- 6. Interactive Customizer UI (UEVR Script UI)
-- -----------------------------------------------------------------------------
local function render_ui()
    imgui.text("====================================================")
    imgui.text_colored("  AC8 TARGET LOCATOR HUD : OFF-SCREEN ARROW", 0xFF00FFCC)
    imgui.text("====================================================")

    local ch_en, val_en = imgui.checkbox("Enable Target Locator Arrow##loc_en", cfg.enabled)
    if ch_en then cfg.enabled = val_en; save_config() end

    imgui.separator()

    -- Target Status
    imgui.text(string.format("Locked Target: %s  |  Distance: %dm", S.target_name, S.target_dist_m))
    imgui.text(string.format("Azimuth: %+.1f deg  |  Elevation: %+.1f deg", S.azimuth_deg, S.elevation_deg))
    if S.is_offscreen then
        imgui.text_colored(string.format(">>> OFF-SCREEN ARROW ACTIVE: Heading %+.1f deg <<<", S.arrow_heading_deg), 0xFF0055FF)
    else
        imgui.text_colored("Target in Boresight (Arrow Hidden)", 0xFF44FF44)
    end

    imgui.separator()

    -- Mode Selection
    imgui.text("Arrow Render Mode:")
    local m0 = (cfg.mode == 0)
    local m1 = (cfg.mode == 1)
    local m2 = (cfg.mode == 2)
    if imgui.radio_button("Mode 0: WBP_LocatorWidget (Native)##m0", m0) then cfg.mode = 0; save_config() end
    imgui.same_line()
    if imgui.radio_button("Mode 1: LandingGuideBar##m1", m1) then cfg.mode = 1; save_config() end
    imgui.same_line()
    if imgui.radio_button("Mode 2: Dual Hybrid##m2", m2) then cfg.mode = 2; save_config() end

    imgui.separator()

    -- Ring Geometry (Co-located with Pitch Ladder)
    imgui.text_colored("【Geometry & Placement (HUD Central Ring)】", 0xFFFFAA00)
    local ch_r, val_r = imgui.slider_float("Ring Radius (px)##loc_r", cfg.ring_radius, 100.0, 800.0)
    if ch_r then cfg.ring_radius = val_r; save_config() end

    local ch_sx, val_sx = imgui.slider_float("Arrow Length (Scale X)##loc_sx", cfg.arrow_scale_x, 0.2, 5.0)
    if ch_sx then cfg.arrow_scale_x = val_sx; save_config() end

    local ch_sy, val_sy = imgui.slider_float("Arrow Width (Scale Y)##loc_sy", cfg.arrow_scale_y, 0.2, 5.0)
    if ch_sy then cfg.arrow_scale_y = val_sy; save_config() end

    local ch_op, val_op = imgui.slider_float("Opacity##loc_op", cfg.arrow_opacity, 0.1, 1.0)
    if ch_op then cfg.arrow_opacity = val_op; save_config() end

    imgui.separator()

    -- Center Offsets
    imgui.text_colored("【Center Offset Alignment】", 0xFFAAAAFF)
    local ch_ox, val_ox = imgui.slider_float("Center Offset X##loc_ox", cfg.center_offset_x, -400.0, 400.0)
    if ch_ox then cfg.center_offset_x = val_ox; save_config() end

    local ch_oy, val_oy = imgui.slider_float("Center Offset Y##loc_oy", cfg.center_offset_y, -400.0, 400.0)
    if ch_oy then cfg.center_offset_y = val_oy; save_config() end

    local ch_th, val_th = imgui.slider_float("FOV Threshold (deg)##loc_th", cfg.angle_threshold, 10.0, 60.0)
    if ch_th then cfg.angle_threshold = val_th; save_config() end

    local ch_inv, val_inv = imgui.checkbox("Invert Arrow Angle##loc_inv", cfg.invert_rotation)
    if ch_inv then cfg.invert_rotation = val_inv; save_config() end

    local ch_aoff, val_aoff = imgui.slider_float("Angle Fine-Tune (deg)##loc_aoff", cfg.angle_offset, -180.0, 180.0)
    if ch_aoff then cfg.angle_offset = val_aoff; save_config() end

    imgui.separator()

    -- Colors
    imgui.text_colored("【Color & Tint】", 0xFF88FF88)
    if imgui.button("HUD Classic Green##col_green") then
        cfg.color_r = 0.0; cfg.color_g = 1.0; cfg.color_b = 0.2; cfg.color_a = 1.0; save_config()
    end
    imgui.same_line()
    if imgui.button("Alert Red##col_red") then
        cfg.color_r = 1.0; cfg.color_g = 0.1; cfg.color_b = 0.1; cfg.color_a = 1.0; save_config()
    end
    imgui.same_line()
    if imgui.button("Cyan Blue##col_cyan") then
        cfg.color_r = 0.0; cfg.color_g = 0.8; cfg.color_b = 1.0; cfg.color_a = 1.0; save_config()
    end

    imgui.separator()

    -- Diagnostics
    imgui.text("Handles Status:")
    imgui.text(string.format("  LocatorWidget: %s", S.locator_widget and "Bound OK" or "Not Found"))
    imgui.text(string.format("  LandingGuideBar: %s", S.landing_guide_bar and "Bound OK" or "Not Found"))

    if imgui.button("Reset Config to Default##btn_reset_cfg") then
        cfg.ring_radius     = 320.0
        cfg.arrow_scale_x   = 1.8
        cfg.arrow_scale_y   = 1.8
        cfg.arrow_opacity   = 1.0
        cfg.center_offset_x = 0.0
        cfg.center_offset_y = 0.0
        cfg.angle_threshold = 22.0
        cfg.invert_rotation = false
        cfg.angle_offset    = 0.0
        cfg.mode            = 0
        cfg.color_r         = 0.0
        cfg.color_g         = 1.0
        cfg.color_b         = 0.2
        cfg.color_a         = 1.0
        save_config()
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully. Co-located with Pitch Ladder.", SCRIPT_NAME))
