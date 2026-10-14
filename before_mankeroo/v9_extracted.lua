--[[
  ============================================================================
  ac8_target_locator_test.lua : Native Target Locator Restoration Test (v9)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Design:     PURE FORCED DISPLAY / DELEGATED ENGINE CALCULATION
              - All position and angle calculations are 100% computed by AC8 C++
              - Lua does NOT override or calculate trigonometry (atan2, cos, sin)
              - TEST A: 2D Native UMG WBP_LocatorWidget & Locator_Wingman unhide
              - TEST B: 3D Native ChronicleTargetContainerActorBP & Pin Billboard unhide
              - Full live telemetry of AC8 native coordinates and pin rotations

  Safety:     100% Pure ASCII, Game-Thread Only (on_post_engine_tick), Crash-Safe
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Locator-Test"
local SCRIPT_VER  = "v9-NativeDelegation"

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
-- State & Configuration Table
-- -----------------------------------------------------------------------------
local S = {
    -- Master Mode:
    -- 1 = TEST A: 2D Native UMG Locator
    -- 2 = TEST B: 3D Native TargetContainer Actor
    -- 3 = BOTH: Simultaneous Test
    test_mode = 1,

    -- TEST A (2D Native UMG WBP_LocatorWidget)
    test_a_enabled          = true,
    test_a_scale            = 2.0,      -- Scale multiplier
    test_a_opacity          = 1.0,      -- Opacity (0.0 - 1.0)
    test_a_unhide_children  = true,     -- Recursively unhide child widgets
    test_a_include_wingman  = true,     -- Also unhide WBP_HUD_Locator_Wingman

    -- TEST B (3D Native TargetContainer Actor)
    test_b_enabled          = false,
    test_b_pin_scale        = 10.0,     -- Scale multiplier for Pin Billboards
    test_b_text_scale       = 3.0,      -- Scale multiplier for Callsign/TGT Text
    test_b_unhide_all_comps = true,     -- Unhide Box, Pins, Callsign, Distance
    test_b_pullback         = false,    -- Optional: Pull distance along AC8 vector
    test_b_pullback_dist_cm = 130.0,    -- Cockpit HUD distance (cm)

    -- Telemetry & Cache
    pawn                    = nil,
    target_actor            = nil,
    target_name             = "None",
    target_dist_m           = 0,
    target_azimuth_deg      = 0.0,
    target_elevation_deg    = 0.0,
    is_offscreen            = false,

    -- 2D Telemetry Cache
    found_2d_locator        = nil,
    found_2d_wingman        = nil,
    found_2d_children       = {},
    native_2d_tx            = 0.0,
    native_2d_ty            = 0.0,
    native_2d_angle         = 0.0,
    native_2d_vis           = -1,
    native_2d_opacity       = 0.0,

    -- 3D Telemetry Cache
    found_3d_containers     = {},
    active_3d_container     = nil,
    native_3d_loc_x         = 0.0,
    native_3d_loc_y         = 0.0,
    native_3d_loc_z         = 0.0,
    native_3d_pin_vis       = false,
    native_3d_callsign      = "None",

    last_scan_tick          = 0,
    log_messages            = {},
}

local function add_log(msg)
    local t = os.date("%H:%M:%S")
    local entry = string.format("[%s] %s", t, msg)
    table.insert(S.log_messages, 1, entry)
    if #S.log_messages > 15 then table.remove(S.log_messages) end
    print(string.format("[%s] %s", SCRIPT_NAME, msg))
end

-- -----------------------------------------------------------------------------
-- Scanner: 2D Native UMG Locator Widgets
-- -----------------------------------------------------------------------------
local function scan_2d_widgets()
    local uw_class = api:find_uobject("Class /Script/UMG.UserWidget")
    if not uw_class then return end

    local all_uw = safe_call(function() return uw_class:get_objects_matching(false) end, {})
    local loc_w = nil
    local wing_w = nil
    local children = {}

    for _, w in ipairs(all_uw) do
        local fn = get_safe_name(w)
        if not fn:find("Default__", 1, true) then
            if fn:find("WBP_LocatorWidget", 1, true) or fn:find("Parts_Locator", 1, true) then
                if fn:find("WidgetTree", 1, true) and fn ~= loc_w then
                    table.insert(children, w)
                else
                    loc_w = w
                end
            elseif fn:find("Locator_Wingman", 1, true) then
                wing_w = w
            end
        end
    end

    S.found_2d_locator = loc_w
    S.found_2d_wingman = wing_w
    S.found_2d_children = children
end

-- -----------------------------------------------------------------------------
-- Scanner: 3D Native Target Containers
-- -----------------------------------------------------------------------------
local function scan_3d_containers()
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    if not actor_class then return end

    local all_actors = safe_call(function() return actor_class:get_objects_matching(false) end, {})
    local list = {}

    for _, a in ipairs(all_actors) do
        local fn = get_safe_name(a)
        if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
            table.insert(list, a)
        end
    end

    S.found_3d_containers = list
end

-- -----------------------------------------------------------------------------
-- Target Tracking & Off-Screen Detection (Reference Telemetry)
-- -----------------------------------------------------------------------------
local function update_target_telemetry()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.pawn = pawn
    if not pawn then return end

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

    -- If no target directly from pawn, use closest ChronicleTargetContainerActor
    if not tgt and #S.found_3d_containers > 0 then
        local p_loc = safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
        local min_dist = 99999999.0
        for _, c in ipairs(S.found_3d_containers) do
            local c_loc = safe_call(function() return c:call("K2_GetActorLocation") end, nil)
            if p_loc and c_loc then
                local dx = (c_loc.X or c_loc.x or 0) - (p_loc.X or p_loc.x or 0)
                local dy = (c_loc.Y or c_loc.y or 0) - (p_loc.Y or p_loc.y or 0)
                local dz = (c_loc.Z or c_loc.z or 0) - (p_loc.Z or p_loc.z or 0)
                local d = dx * dx + dy * dy + dz * dz
                if d < min_dist then
                    min_dist = d
                    tgt = c
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
            local ndx, ndy, ndz = dx / dist_cm, dy / dist_cm, dz / dist_cm

            local pitch = math.rad(p_rot.Pitch or p_rot.pitch or 0)
            local yaw   = math.rad(p_rot.Yaw or p_rot.yaw or 0)
            local roll  = math.rad(p_rot.Roll or p_rot.roll or 0)

            local cos_y, sin_y = math.cos(-yaw), math.sin(-yaw)
            local x1 = ndx * cos_y - ndy * sin_y
            local y1 = ndx * sin_y + ndy * cos_y
            local z1 = ndz

            local cos_p, sin_p = math.cos(-pitch), math.sin(-pitch)
            local x2 = x1 * cos_p + z1 * sin_p
            local y2 = y1
            local z2 = -x1 * sin_p + z1 * cos_p

            local cos_r, sin_r = math.cos(-roll), math.sin(-roll)
            local local_x = x2
            local local_y = y2 * cos_r - z2 * sin_r
            local local_z = y2 * sin_r + z2 * cos_r

            local az_deg = math.deg(math.atan(local_y, math.max(0.001, local_x)))
            local el_deg = math.deg(math.atan(local_z, math.max(0.001, local_x)))
            if local_x < 0 then
                if local_y >= 0 then az_deg = 180.0 - az_deg else az_deg = -180.0 - az_deg end
            end

            S.target_azimuth_deg = az_deg
            S.target_elevation_deg = el_deg

            local angle_off = math.sqrt(az_deg * az_deg + el_deg * el_deg)
            S.is_offscreen = (angle_off > 20.0) or (local_x < 0)
        end
    end
end

-- -----------------------------------------------------------------------------
-- Execution Logic: TEST A (2D Native UMG Pure Forced Display)
-- -----------------------------------------------------------------------------
local function tick_test_a()
    local w = S.found_2d_locator
    if not w or not is_valid(w) then return end

    -- Read native telemetry before modification
    pcall(function()
        S.native_2d_vis = w:call("GetVisibility") or -1
        S.native_2d_opacity = w.RenderOpacity or 0.0
        local rt = w.RenderTransform
        if rt then
            if rt.Translation then
                S.native_2d_tx = rt.Translation.X or rt.Translation.x or 0.0
                S.native_2d_ty = rt.Translation.Y or rt.Translation.y or 0.0
            end
            S.native_2d_angle = rt.Angle or rt.angle or 0.0
        end
    end)

    -- Apply Pure Forced Display (Visibility + Opacity + Scale)
    -- We NEVER modify RenderTranslation or RenderTransform.Angle! AC8 C++ controls them!
    pcall(function()
        w:call("SetVisibility", 0) -- 0 = Visible
        w.RenderOpacity = S.test_a_opacity
        if w.SetRenderScale then
            w:SetRenderScale({ X = S.test_a_scale, Y = S.test_a_scale })
        end
    end)

    -- Recursively unhide child widgets if enabled
    if S.test_a_unhide_children then
        for _, child in ipairs(S.found_2d_children) do
            if is_valid(child) then
                pcall(function()
                    child:call("SetVisibility", 0)
                    child.RenderOpacity = S.test_a_opacity
                end)
            end
        end
    end

    -- Also unhide Wingman locator if enabled
    if S.test_a_include_wingman and S.found_2d_wingman and is_valid(S.found_2d_wingman) then
        pcall(function()
            S.found_2d_wingman:call("SetVisibility", 0)
            S.found_2d_wingman.RenderOpacity = S.test_a_opacity
            if S.found_2d_wingman.SetRenderScale then
                S.found_2d_wingman:SetRenderScale({ X = S.test_a_scale, Y = S.test_a_scale })
            end
        end)
    end
end

-- -----------------------------------------------------------------------------
-- Execution Logic: TEST B (3D Native ChronicleTargetContainerActorBP Pure Forced Display)
-- -----------------------------------------------------------------------------
local function tick_test_b()
    if #S.found_3d_containers == 0 then return end

    local p_loc = S.pawn and safe_call(function() return S.pawn:call("K2_GetActorLocation") end, nil)

    for idx, actor in ipairs(S.found_3d_containers) do
        if is_valid(actor) then
            -- Read native telemetry
            local a_loc = safe_call(function() return actor:call("K2_GetActorLocation") end, nil)
            if a_loc and idx == 1 then
                S.native_3d_loc_x = a_loc.X or a_loc.x or 0.0
                S.native_3d_loc_y = a_loc.Y or a_loc.y or 0.0
                S.native_3d_loc_z = a_loc.Z or a_loc.z or 0.0
                S.active_3d_container = actor
            end

            -- 1. Unhide Actor itself
            pcall(function()
                actor:call("SetActorHiddenInGame", false)
                actor.bHidden = false
            end)

            -- 2. Unhide Components (Pins, Boxes, Text)
            local pin_c   = safe_call(function() return actor.ClockTargetPinBillboardImage end, nil)
            local pin_a   = safe_call(function() return actor.AntiClockTargetPinBillboardImage end, nil)
            local box     = safe_call(function() return actor.ContainerBox end, nil)
            local call_t  = safe_call(function() return actor.ObjectCallsignText end, nil)
            local type_t  = safe_call(function() return actor.ObjectTypeText end, nil)
            local dist_t  = safe_call(function() return actor.DistanceText end, nil)

            -- Clockwise Pin
            if pin_c then
                pcall(function()
                    pin_c:call("SetHiddenInGame", false)
                    pin_c:call("SetVisibility", true)
                    pin_c.bHiddenInGame = false
                    pin_c:SetRelativeScale3D({ X = S.test_b_pin_scale, Y = S.test_b_pin_scale, Z = S.test_b_pin_scale })
                    if idx == 1 then S.native_3d_pin_vis = true end
                end)
            end

            -- Anti-Clockwise Pin
            if pin_a then
                pcall(function()
                    pin_a:call("SetHiddenInGame", false)
                    pin_a:call("SetVisibility", true)
                    pin_a.bHiddenInGame = false
                    pin_a:SetRelativeScale3D({ X = S.test_b_pin_scale, Y = S.test_b_pin_scale, Z = S.test_b_pin_scale })
                end)
            end

            -- Callsign (e.g. MQ-99) & Type (TGT) Text
            if call_t then
                pcall(function()
                    call_t:call("SetHiddenInGame", false)
                    call_t:call("SetVisibility", true)
                    call_t.bHiddenInGame = false
                    call_t:SetRelativeScale3D({ X = S.test_b_text_scale, Y = S.test_b_text_scale, Z = S.test_b_text_scale })
                end)
            end

            if type_t then
                pcall(function()
                    type_t:call("SetHiddenInGame", false)
                    type_t:call("SetVisibility", true)
                    type_t.bHiddenInGame = false
                    type_t:SetRelativeScale3D({ X = S.test_b_text_scale, Y = S.test_b_text_scale, Z = S.test_b_text_scale })
                end)
            end

            if dist_t and S.test_b_unhide_all_comps then
                pcall(function()
                    dist_t:call("SetHiddenInGame", false)
                    dist_t:call("SetVisibility", true)
                    dist_t.bHiddenInGame = false
                end)
            end

            if box and S.test_b_unhide_all_comps then
                pcall(function()
                    box:call("SetHiddenInGame", false)
                    box:call("SetVisibility", true)
                    box.bHiddenInGame = false
                end)
            end

            -- 3. Optional: Distance Pullback along AC8's Exact Native Vector
            -- Notice: Direction vector is 100% determined by AC8! Lua only shortens the distance.
            if S.test_b_pullback and p_loc and a_loc then
                local dx = (a_loc.X or a_loc.x or 0) - (p_loc.X or p_loc.x or 0)
                local dy = (a_loc.Y or a_loc.y or 0) - (p_loc.Y or p_loc.y or 0)
                local dz = (a_loc.Z or a_loc.z or 0) - (p_loc.Z or p_loc.z or 0)
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if d > 10.0 then
                    local scale = S.test_b_pullback_dist_cm / d
                    local new_loc = {
                        X = (p_loc.X or p_loc.x or 0) + dx * scale,
                        Y = (p_loc.Y or p_loc.y or 0) + dy * scale,
                        Z = (p_loc.Z or p_loc.z or 0) + dz * scale,
                    }
                    pcall(function()
                        actor:call("K2_SetActorLocation", new_loc, false, nil, false)
                    end)
                end
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Main Engine Tick
-- -----------------------------------------------------------------------------
local frame_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    frame_count = frame_count + 1

    -- Periodic rescan of widgets and actors
    if frame_count - S.last_scan_tick >= 120 then
        S.last_scan_tick = frame_count
        scan_2d_widgets()
        scan_3d_containers()
    end

    -- Frequently update target telemetry
    if frame_count % 3 == 0 then
        update_target_telemetry()
    end

    -- Run active tests
    if S.test_mode == 1 or S.test_mode == 3 then
        tick_test_a()
    end
    if S.test_mode == 2 or S.test_mode == 3 then
        tick_test_b()
    end
end)

-- -----------------------------------------------------------------------------
-- Interactive ImGui Control Panel (UEVR Script UI)
-- -----------------------------------------------------------------------------
local function render_ui()
    imgui.text("================================================================")
    imgui.text_colored("   AC8 NATIVE TARGET LOCATOR RESTORATION TEST (" .. SCRIPT_VER .. ")", 0xFF00FFCC)
    imgui.text("================================================================")

    -- Status Header
    imgui.text(string.format("Target: %-16s | Distance: %5dm | OffScreen: %s",
        S.target_name, S.target_dist_m, S.is_offscreen and "[YES - OUTSIDE]" or "[NO - IN VIEW]"))
    imgui.text(string.format("Azimuth: %+6.1f deg | Elevation: %+6.1f deg",
        S.target_azimuth_deg, S.target_elevation_deg))

    imgui.separator()

    -- -------------------------------------------------------------------------
    -- TEST MODE SELECTOR
    -- -------------------------------------------------------------------------
    imgui.text_colored("【SELECT EXPERIMENT MODE】", 0xFFFFFF00)
    
    local m_a = (S.test_mode == 1)
    local m_b = (S.test_mode == 2)
    local m_both = (S.test_mode == 3)

    if imgui.radio_button("TEST A: 2D Native WBP_LocatorWidget (UMG Screen-Edge Arrow)##m1", m_a) then
        S.test_mode = 1
        add_log("Switched to TEST A (2D Native UMG Locator)")
    end
    imgui.same_line()
    if imgui.radio_button("TEST B: 3D Native TargetContainer Actor (World Pins)##m2", m_b) then
        S.test_mode = 2
        add_log("Switched to TEST B (3D Native TargetContainer)")
    end
    imgui.same_line()
    if imgui.radio_button("BOTH Active##m3", m_both) then
        S.test_mode = 3
        add_log("Switched to BOTH Active")
    end

    imgui.separator()

    -- -------------------------------------------------------------------------
    -- TEST A CONTROLS & MONITOR
    -- -------------------------------------------------------------------------
    if S.test_mode == 1 or S.test_mode == 3 then
        imgui.text_colored(">>> [TEST A: 2D Native UMG Locator Controls] <<<", 0xFF00FF88)
        imgui.text(string.format("  Locator Widget Status: %s | Children: %d",
            S.found_2d_locator and "DETECTED (Bound OK)" or "NOT FOUND (Scanning...)",
            #S.found_2d_children))

        local ch_sc, val_sc = imgui.slider_float("2D Scale Multiplier##a_sc", S.test_a_scale, 0.5, 6.0)
        if ch_sc then S.test_a_scale = val_sc end

        local ch_op, val_op = imgui.slider_float("2D Opacity##a_op", S.test_a_opacity, 0.1, 1.0)
        if ch_op then S.test_a_opacity = val_op end

        local ch_ch, val_ch = imgui.checkbox("Force Unhide Child Canvas/Widgets##a_ch", S.test_a_unhide_children)
        if ch_ch then S.test_a_unhide_children = val_ch end
        imgui.same_line()
        local ch_wg, val_wg = imgui.checkbox("Include Wingman Locator##a_wg", S.test_a_include_wingman)
        if ch_wg then S.test_a_include_wingman = val_wg end

        -- 2D Native Telemetry Display (Read directly from AC8 C++)
        imgui.text_colored("  [AC8 Native C++ Computed Telemetry]:", 0xFFAAAAAA)
        imgui.text(string.format("    Native Translation: (X = %+.1f, Y = %+.1f)", S.native_2d_tx, S.native_2d_ty))
        imgui.text(string.format("    Native Angle:       %+.1f deg", S.native_2d_angle))
        imgui.text(string.format("    Native Visibility:  %d (0=Visible, 4=SelfHitTestInv)", S.native_2d_vis))

        imgui.separator()
    end

    -- -------------------------------------------------------------------------
    -- TEST B CONTROLS & MONITOR
    -- -------------------------------------------------------------------------
    if S.test_mode == 2 or S.test_mode == 3 then
        imgui.text_colored(">>> [TEST B: 3D Native TargetContainer Actor Controls] <<<", 0xFFFF8800)
        imgui.text(string.format("  Active Target Containers in Memory: %d", #S.found_3d_containers))

        local ch_psc, val_psc = imgui.slider_float("Pin Billboard Scale (3D Arrow)##b_psc", S.test_b_pin_scale, 1.0, 30.0)
        if ch_psc then S.test_b_pin_scale = val_psc end

        local ch_tsc, val_tsc = imgui.slider_float("Callsign / TGT Text Scale##b_tsc", S.test_b_text_scale, 0.5, 10.0)
        if ch_tsc then S.test_b_text_scale = val_tsc end

        local ch_all, val_all = imgui.checkbox("Unhide All Components (Box, Pins, Dist)##b_all", S.test_b_unhide_all_comps)
        if ch_all then S.test_b_unhide_all_comps = val_all end

        -- Optional Distance Pullback
        imgui.text_colored("  [Cockpit Distance Clamping (Optional)]:", 0xFFCCCCCC)
        local ch_pb, val_pb = imgui.checkbox("Pull Distance to Cockpit HUD Plane##b_pb", S.test_b_pullback)
        if ch_pb then S.test_b_pullback = val_pb end

        if S.test_b_pullback then
            imgui.same_line()
            local ch_pbd, val_pbd = imgui.slider_float("Distance (cm)##b_pbd", S.test_b_pullback_dist_cm, 50.0, 300.0)
            if ch_pbd then S.test_b_pullback_dist_cm = val_pbd end
        end

        -- 3D Native Telemetry Display (Read directly from AC8 C++)
        imgui.text_colored("  [AC8 Native C++ Target Container Telemetry]:", 0xFFAAAAAA)
        imgui.text(string.format("    Container Location: (X = %.0f, Y = %.0f, Z = %.0f)",
            S.native_3d_loc_x, S.native_3d_loc_y, S.native_3d_loc_z))
        imgui.text(string.format("    Pin Visible Status: %s", S.native_3d_pin_vis and "ACTIVE (Unhidden)" or "Hidden/None"))

        imgui.separator()
    end

    -- Manual Refresh
    if imgui.button("Force Rescan Memory Now##btn_rescan") then
        scan_2d_widgets()
        scan_3d_containers()
        update_target_telemetry()
        add_log("Manual memory rescan completed.")
    end

    -- Diagnostic Logs
    imgui.text("Recent Action Log:")
    for _, line in ipairs(S.log_messages) do
        imgui.text_colored(line, 0xFF88CCFF)
    end
end

-- -----------------------------------------------------------------------------
-- Register UI & Startup
-- -----------------------------------------------------------------------------
if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

scan_2d_widgets()
scan_3d_containers()
update_target_telemetry()
add_log("Target Locator v9 loaded. Engine delegation active.")
