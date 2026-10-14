--[[
  ============================================================================
  ac8_locator_experiment_v1.lua : Target Off-Screen Arrow (Locator) Diagnostic & Experiment
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Purpose:    Investigate and restore the "Off-Screen Target Arrow (Locator)"
              Testing hypotheses:
                1. Hypothesis A (User's Theory): 3D Object placed far away / in 3D HUD layer
                2. Hypothesis B: 2D UMG WBP_LocatorWidget suppressed or locked at (0,0)
                3. Hypothesis C: TargetContainerActor ClockTargetPinBillboardImage
                4. Hypothesis D: Synthetic dynamic direction arrow (JHMCS-style fallback)
  Compatibility: 100% Pure ASCII for UEVR Lua 1.05 / DirectX 12 crash-safe
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Locator-Experiment-v1"

--------------------------------------------------------------------------
-- 0. Safe Utility Functions
--------------------------------------------------------------------------
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

--------------------------------------------------------------------------
-- 1. State Table
--------------------------------------------------------------------------
local S = {
    -- Telemetry
    pawn                = nil,
    target_actor        = nil,
    target_name         = "None",
    target_dist_m       = 0,
    target_azimuth_deg  = 0.0,
    target_elevation_deg= 0.0,
    is_offscreen        = false,
    offscreen_threshold = 25.0, -- degrees from boresight

    -- Case A: UMG WBP_LocatorWidget
    locator_widgets     = {},
    c_a_force_visible   = false,
    c_a_scale           = 1.0,
    c_a_offset_x        = 0.0,
    c_a_offset_y        = 0.0,
    c_a_unlock_rt       = false, -- unlock from (0,0) clamp

    -- Case B: 3D Objects & Hierarchy Scan (Locator/Arrow/Pointer in 3D)
    found_3d_candidates = {},
    c_b_bring_close     = false,
    c_b_target_index    = 1,
    c_b_scale_3d        = 1.0,

    -- Case C: Target Pin Billboards (Inside TargetContainer)
    target_containers   = {},
    c_c_pins_visible    = false,
    c_c_pins_scale      = 1.0,

    -- Case D: Synthetic Direction Indicator (Visual HUD Guide)
    c_d_synthetic_guide = false,
    c_d_guide_radius    = 350.0, -- pixel radius from center
    c_d_guide_size      = 30.0,

    -- UI / Logging
    log_messages        = {},
    max_logs            = 12,
}

local function add_log(msg)
    local t = os.date("%H:%M:%S")
    table.insert(S.log_messages, string.format("[%s] %s", t, msg))
    if #S.log_messages > S.max_logs then
        table.remove(S.log_messages, 1)
    end
    print(string.format("[%s] %s", SCRIPT_NAME, msg))
end

--------------------------------------------------------------------------
-- 2. Scanner: 2D UMG Widgets (WBP_LocatorWidget & DynamicDrawCanvas)
--------------------------------------------------------------------------
local function scan_umg_widgets()
    local uw_class = api:find_uobject("Class /Script/UMG.UserWidget")
    if not uw_class then return end

    local all_uw = safe_call(function() return uw_class:get_objects_matching(false) end, {})
    local found = {}

    for _, w in ipairs(all_uw) do
        local fn = get_safe_name(w)
        if fn:find("Locator", 1, true) or fn:find("TargetSelectionDraw", 1, true) then
            if not fn:find("Default__", 1, true) then
                local vis = safe_call(function() return w:call("GetVisibility") end, -1)
                local sn = get_short_name(w)
                table.insert(found, {
                    widget = w,
                    name   = sn,
                    full   = fn,
                    vis    = vis,
                })
            end
        end
    end

    S.locator_widgets = found
    add_log(string.format("UMG Scan: Found %d Locator/Selection widget(s)", #found))
end

--------------------------------------------------------------------------
-- 3. Scanner: 3D Objects & Components (Hypothesis A: Far Away / 3D HUD)
--------------------------------------------------------------------------
local function scan_3d_candidates()
    local candidates = {}

    -- Scan Actors
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    if actor_class then
        local all_actors = safe_call(function() return actor_class:get_objects_matching(false) end, {})
        for _, a in ipairs(all_actors) do
            local fn = get_safe_name(a)
            if not fn:find("Default__", 1, true) then
                if fn:find("Locator", 1, true) or fn:find("Arrow", 1, true) or 
                   fn:find("TargetGuide", 1, true) or fn:find("DirectionIndicator", 1, true) or
                   fn:find("LiveMainHUDParent", 1, true) or fn:find("AerialRefuel3D", 1, true) then
                    
                    local loc = safe_call(function() return a:call("K2_GetActorLocation") end, nil)
                    table.insert(candidates, {
                        obj   = a,
                        is_act= true,
                        name  = get_short_name(a),
                        full  = fn,
                        loc   = loc,
                    })
                end
            end
        end
    end

    -- Scan Components of Player Pawn & HUD
    local pawn = S.pawn
    if pawn then
        local comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
        if comp_class then
            local comps = safe_call(function() return pawn:call("K2_GetComponentsByClass", comp_class) end, {})
            for _, c in ipairs(comps) do
                local fn = get_safe_name(c)
                if fn:find("Arrow", 1, true) or fn:find("Locator", 1, true) or 
                   fn:find("Target", 1, true) or fn:find("Indicator", 1, true) or fn:find("Billboard", 1, true) then
                    table.insert(candidates, {
                        obj   = c,
                        is_act= false,
                        name  = get_short_name(c) .. " (PawnComp)",
                        full  = fn,
                        loc   = nil,
                    })
                end
            end
        end
    end

    -- Scan Target Containers
    local tc_found = {}
    if actor_class then
        local all_actors = safe_call(function() return actor_class:get_objects_matching(false) end, {})
        for _, a in ipairs(all_actors) do
            local fn = get_safe_name(a)
            if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
                local cb = safe_call(function() return a.ContainerBox end, nil)
                local pin_c = safe_call(function() return a.ClockTargetPinBillboardImage end, nil)
                local pin_a = safe_call(function() return a.AntiClockTargetPinBillboardImage end, nil)
                table.insert(tc_found, {
                    actor = a,
                    name  = get_short_name(a),
                    pin_clock = pin_c,
                    pin_anti  = pin_a,
                })
            end
        end
    end
    S.target_containers = tc_found

    S.found_3d_candidates = candidates
    add_log(string.format("3D Scan: %d Candidate(s), %d TargetContainer(s)", #candidates, #tc_found))
end

--------------------------------------------------------------------------
-- 4. Target & Relative Angle Math (Azimuth / Elevation Calculation)
--------------------------------------------------------------------------
local function update_target_telemetry()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.pawn = pawn
    if not pawn then return end

    -- Fetch Target from TargetSelection Component
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
    S.target_actor = tgt

    if not tgt then
        S.target_name = "No Target Selected"
        S.target_dist_m = 0
        S.target_azimuth_deg = 0.0
        S.target_elevation_deg = 0.0
        S.is_offscreen = false
        return
    end

    S.target_name = get_short_name(tgt)

    -- Actor World Locations
    local p_loc = safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
    local t_loc = safe_call(function() return tgt:call("K2_GetActorLocation") end, nil)
    local p_rot = safe_call(function() return pawn:call("K2_GetActorRotation") end, nil)

    if p_loc and t_loc and p_rot then
        local dx = (t_loc.X or t_loc.x or 0) - (p_loc.X or p_loc.x or 0)
        local dy = (t_loc.Y or t_loc.y or 0) - (p_loc.Y or p_loc.y or 0)
        local dz = (t_loc.Z or t_loc.z or 0) - (p_loc.Z or p_loc.z or 0)
        local dist_cm = math.sqrt(dx * dx + dy * dy + dz * dz)
        S.target_dist_m = math.floor(dist_cm / 100.0)

        if dist_cm > 1.0 then
            -- Normalize direction vector in World Space
            local ndx, ndy, ndz = dx / dist_cm, dy / dist_cm, dz / dist_cm

            -- Pawn rotation (Pitch, Yaw, Roll in degrees)
            local pitch = math.rad(p_rot.Pitch or p_rot.pitch or 0)
            local yaw   = math.rad(p_rot.Yaw or p_rot.yaw or 0)
            local roll  = math.rad(p_rot.Roll or p_rot.roll or 0)

            -- Transform to Pawn Local Space (Forward: X, Right: Y, Up: Z)
            -- 1. Yaw rotation (Z-axis)
            local cos_y, sin_y = math.cos(-yaw), math.sin(-yaw)
            local x1 = ndx * cos_y - ndy * sin_y
            local y1 = ndx * sin_y + ndy * cos_y
            local z1 = ndz

            -- 2. Pitch rotation (Y-axis)
            local cos_p, sin_p = math.cos(-pitch), math.sin(-pitch)
            local x2 = x1 * cos_p + z1 * sin_p
            local y2 = y1
            local z2 = -x1 * sin_p + z1 * cos_p

            -- 3. Roll rotation (X-axis)
            local cos_r, sin_r = math.cos(-roll), math.sin(-roll)
            local local_x = x2
            local local_y = y2 * cos_r - z2 * sin_r
            local local_z = y2 * sin_r + z2 * cos_r

            -- Local angles from Boresight (Forward)
            -- Azimuth: positive = right, negative = left
            -- Elevation: positive = up, negative = down
            local az_deg = math.deg(math.atan(local_y, math.max(0.001, local_x)))
            local el_deg = math.deg(math.atan(local_z, math.max(0.001, local_x)))

            if local_x < 0 then
                -- Behind the aircraft
                if local_y >= 0 then az_deg = 180.0 - az_deg else az_deg = -180.0 - az_deg end
            end

            S.target_azimuth_deg = az_deg
            S.target_elevation_deg = el_deg

            local angle_from_center = math.sqrt(az_deg * az_deg + el_deg * el_deg)
            S.is_offscreen = (angle_from_center > S.offscreen_threshold) or (local_x < 0)
        end
    end
end

--------------------------------------------------------------------------
-- 5. Execution Loops (Tick)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan
    if tick_count % 90 == 0 then
        update_target_telemetry()
    else
        -- Update angle frequently
        if tick_count % 3 == 0 then
            update_target_telemetry()
        end
    end

    -- Case A: UMG Enforcement
    if S.c_a_force_visible then
        for _, entry in ipairs(S.locator_widgets) do
            local w = entry.widget
            if w then
                pcall(function()
                    -- Force Visible (0 = Visible, 4 = SelfHitTestInvisible)
                    w:call("SetVisibility", 0)
                    w.RenderOpacity = 1.0
                    w:SetRenderScale({ X = S.c_a_scale, Y = S.c_a_scale })
                    if S.c_a_unlock_rt then
                        w:SetRenderTranslation({ X = S.c_a_offset_x, Y = S.c_a_offset_y })
                    end
                end)
            end
        end
    end

    -- Case C: Target Pin Billboards
    if S.c_c_pins_visible then
        for _, entry in ipairs(S.target_containers) do
            local pc = entry.pin_clock
            local pa = entry.pin_anti
            if pc then
                pcall(function()
                    pc:call("SetVisibility", true)
                    pc.bHiddenInGame = false
                    pc:SetRelativeScale3D({ X = S.c_c_pins_scale, Y = S.c_c_pins_scale, Z = S.c_c_pins_scale })
                end)
            end
            if pa then
                pcall(function()
                    pa:call("SetVisibility", true)
                    pa.bHiddenInGame = false
                    pa:SetRelativeScale3D({ X = S.c_c_pins_scale, Y = S.c_c_pins_scale, Z = S.c_c_pins_scale })
                end)
            end
        end
    end
end)

--------------------------------------------------------------------------
-- 6. Interactive ImGui Control Panel (UEVR Script UI)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("====================================================")
    imgui.text_colored("  AC8 TARGET OFF-SCREEN ARROW (LOCATOR) EXPERIMENT", 0xFF00FFCC)
    imgui.text("====================================================")

    -- Status Section
    imgui.text(string.format("Target: %s  |  Distance: %dm", S.target_name, S.target_dist_m))
    imgui.text(string.format("Azimuth: %+.1f deg  |  Elevation: %+.1f deg", S.target_azimuth_deg, S.target_elevation_deg))
    if S.is_offscreen then
        imgui.text_colored(">>> TARGET IS OFF-SCREEN (Arrow should be active!) <<<", 0xFF0044FF)
    else
        imgui.text_colored("--- Target inside HUD Boresight (Reticle in view) ---", 0xFF44FF44)
    end

    local ch_th, val_th = imgui.slider_float("Off-Screen Angle Threshold (deg)##th", S.offscreen_threshold, 10.0, 60.0)
    if ch_th then S.offscreen_threshold = val_th end

    imgui.separator()

    -- --------------------------------------------------------------------
    -- EXPERIMENT A: UMG WBP_LocatorWidget
    -- --------------------------------------------------------------------
    imgui.text_colored("【Experiment A: 2D UMG WBP_LocatorWidget Inspection】", 0xFFFFAA00)
    imgui.text(string.format("Detected Locator Widgets in Memory: %d", #S.locator_widgets))
    for i, w in ipairs(S.locator_widgets) do
        imgui.text(string.format("  [%d] %s", i, w.name))
    end

    if imgui.button("Scan UMG Widgets##btn_scan_umg") then
        scan_umg_widgets()
    end
    imgui.same_line()
    local ch_vis, val_vis = imgui.checkbox("Force Visible & Opacity 1.0##a_vis", S.c_a_force_visible)
    if ch_vis then S.c_a_force_visible = val_vis end

    local ch_sc, val_sc = imgui.slider_float("Widget Scale (Size)##a_sc", S.c_a_scale, 0.5, 5.0)
    if ch_sc then S.c_a_scale = val_sc end

    local ch_un, val_un = imgui.checkbox("Unlock & Test Manual Translation##a_un", S.c_a_unlock_rt)
    if ch_un then S.c_a_unlock_rt = val_un end

    if S.c_a_unlock_rt then
        local ch_x, val_x = imgui.slider_float("Offset X##a_ox", S.c_a_offset_x, -1920.0, 1920.0)
        if ch_x then S.c_a_offset_x = val_x end
        local ch_y, val_y = imgui.slider_float("Offset Y##a_oy", S.c_a_offset_y, -1080.0, 1080.0)
        if ch_y then S.c_a_offset_y = val_y end
        if imgui.button("Center Screen (0,0)##btn_center") then S.c_a_offset_x = 0; S.c_a_offset_y = 0 end
        imgui.same_line()
        if imgui.button("Top Edge (0,-400)##btn_top") then S.c_a_offset_x = 0; S.c_a_offset_y = -400 end
        imgui.same_line()
        if imgui.button("Right Edge (+600,0)##btn_right") then S.c_a_offset_x = 600; S.c_a_offset_y = 0 end
    end

    imgui.separator()

    -- --------------------------------------------------------------------
    -- EXPERIMENT B: 3D Objects & Hierarchy Scan (Hypothesis A)
    -- --------------------------------------------------------------------
    imgui.text_colored("【Experiment B: 3D Arrow Objects & Distance Probe】", 0xFF00AAFF)
    imgui.text("Investigating user theory: 'Drawn in 3D far away like Pitch Ladder'")
    imgui.text(string.format("Found 3D Candidates: %d", #S.found_3d_candidates))

    if imgui.button("Scan 3D Candidates in World##btn_scan_3d") then
        scan_3d_candidates()
    end

    for idx, c in ipairs(S.found_3d_candidates) do
        local loc_str = "No Loc"
        if c.loc then
            loc_str = string.format("(%.0f, %.0f, %.0f)", c.loc.X or c.loc.x or 0, c.loc.Y or c.loc.y or 0, c.loc.Z or c.loc.z or 0)
        end
        imgui.text(string.format("  [%02d] %s | Loc: %s", idx, c.name, loc_str))
    end

    imgui.separator()

    -- --------------------------------------------------------------------
    -- EXPERIMENT C: Target Container Pins
    -- --------------------------------------------------------------------
    imgui.text_colored("【Experiment C: Target Container Pin Billboards】", 0xFFFF55AA)
    imgui.text(string.format("Target Containers: %d", #S.target_containers))

    local ch_pvis, val_pvis = imgui.checkbox("Force Clock/AntiClock Pins Visible##c_pvis", S.c_c_pins_visible)
    if ch_pvis then S.c_c_pins_visible = val_pvis end

    local ch_psc, val_psc = imgui.slider_float("Pin Billboard Scale##c_psc", S.c_c_pins_scale, 0.5, 20.0)
    if ch_psc then S.c_c_pins_scale = val_psc end

    imgui.separator()

    -- --------------------------------------------------------------------
    -- EXPERIMENT D: Synthetic Direction Indicator (JHMCS-style Fallback)
    -- --------------------------------------------------------------------
    imgui.text_colored("【Experiment D: Direction Arrow Angle Simulation】", 0xFF55FF55)
    imgui.text("Calculates dynamic off-screen arrow heading from player boresight:")
    if S.is_offscreen then
        -- Arrow angle on clock face (0 deg = 12 o'clock / Up)
        local arrow_angle_rad = math.atan(S.target_azimuth_deg, S.target_elevation_deg)
        local arrow_angle_deg = math.deg(arrow_angle_rad)
        imgui.text_colored(string.format(">> ARROW HEADING: %+.1f deg (Points toward enemy)", arrow_angle_deg), 0xFFFFFF00)
    else
        imgui.text("Target in boresight. Arrow inactive.")
    end

    imgui.separator()

    -- Diagnostic Logs
    imgui.text("Recent Activity Log:")
    for _, l in ipairs(S.log_messages) do
        imgui.text(l)
    end
end

--------------------------------------------------------------------------
-- 7. Register UI & Initialize
--------------------------------------------------------------------------
if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

-- Run initial scans
scan_umg_widgets()
scan_3d_candidates()
update_target_telemetry()

add_log("Target Locator Diagnostic loaded successfully.")
