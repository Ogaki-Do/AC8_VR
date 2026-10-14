--[[
  ============================================================================
  ac8_m_jhmcs.lua : VR Native 350° FOV & Target Tracking Diagnostic (v15)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenVR / OpenXR
  Architecture:
    1. Deep Reflection Diagnostic:
       Extracts full UClass properties and UFunctions of:
       - LiveTargetContainerManager
       - ChronicleTargetContainerActorBP
       - LiveTargetSelectionComponent
    2. Real-Time Off-Screen Coordinate Comparison:
       Compares the physical 3D world location of the locked enemy aircraft
       (SelectedTarget) against the HUD target container (ChronicleTargetContainerActorBP)
       to determine whether off-screen targets are:
       - Followed in true 3D space
       - Clamped / sucked behind the plane by 2D screen projection
       - Parked at a standby location
    3. Output:
       Writes full diagnostic dump to: data/ac8_target_tracking_truth.txt
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-JHMCS"
local SCRIPT_VER  = "v15-TargetTruth"

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
    -- 1. JHMCS Manual Override (Default: false)
    jhmcs_manual_override = false,

    -- 2. Native FOV Expansion
    native_fov_enabled    = true,
    native_fov            = 350.0,
    applied_fov           = -1.0,
    current_pcm_fov       = 0.0,

    -- 3. Target Marker Scaling
    target_scale          = 1.0,
    applied_scale         = -1.0,

    -- 4. Target Tracking
    max_combat_dist_m     = 22000,
    containers            = {},
    player_pawn           = nil,
    total_slots           = 0,
    active_in_range       = 0,
    wingman_count         = 0,
    enemy_count           = 0,

    -- 5. Real-Time Diagnostics
    sel_target_name       = "None",
    sel_target_dist       = 0.0,
    sel_target_fwd        = 0.0,
    sel_target_right      = 0.0,
    sel_target_up         = 0.0,
    cont1_dist            = 0.0,
    cont1_fwd             = 0.0,
    cont1_right           = 0.0,
    cont1_up              = 0.0,
    delta_dist            = -1.0,
}

--------------------------------------------------------------------------
-- 2. Target Container & Component Caching
--------------------------------------------------------------------------
local container_class = nil
local comp_class      = nil

local function scan_targets()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.player_pawn = pawn

    if not container_class then
        container_class = api:find_uobject("Class /Script/Live.LiveTargetContainerActor")
                       or api:find_uobject("BlueprintGeneratedClass /Game/UI/Material/HUD/TargetContainer3DUI/ChronicleTargetContainerActorBP.ChronicleTargetContainerActorBP_C")
    end

    if not comp_class then
        comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    end

    local raw_actors = {}
    if container_class then
        raw_actors = safe_call(function() return container_class:get_objects_matching(false) end, {}) or {}
    end

    if #raw_actors == 0 then
        local actor_class = api:find_uobject("Class /Script/Engine.Actor")
        local all = actor_class and safe_call(function() return actor_class:get_objects_matching(false) end, {}) or {}
        for _, a in ipairs(all) do
            local fn = get_safe_name(a)
            if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
                table.insert(raw_actors, a)
            end
        end
    end

    local existing_map = {}
    for _, old_entry in ipairs(S.containers) do
        if old_entry.obj then
            existing_map[old_entry.obj] = old_entry
        end
    end

    local found = {}
    for _, a in ipairs(raw_actors) do
        local fn = get_safe_name(a)
        if not fn:find("Default__", 1, true) then
            local old = existing_map[a]
            local comps = (old and old.comps) or {}

            if #comps == 0 and comp_class then
                local raw_comps = safe_call(function() return a:call("K2_GetComponentsByClass", comp_class) end, {}) or {}
                for _, c in ipairs(raw_comps) do
                    table.insert(comps, c)
                end
            end

            table.insert(found, {
                obj          = a,
                name         = get_short_name(a),
                root         = safe_call(function() return a.RootComponent end, nil),
                cb           = safe_call(function() return a.ContainerBox end, nil),
                eb           = safe_call(function() return a.EscortBillboardImage end, nil),
                txt_dist     = safe_call(function() return a.DistanceText end, nil),
                txt_callsign = safe_call(function() return a.ObjectCallsignText end, nil),
                txt_alliance = safe_call(function() return a.AllianceText end, nil),
                comps        = comps,
                dist_m       = old and old.dist_m or 0,
            })
        end
    end

    S.containers = found
    S.total_slots = #found
    S.applied_scale = -1.0
end

--------------------------------------------------------------------------
-- 3. Comprehensive Reflection & Tracking Truth Probe
--------------------------------------------------------------------------
local probe_executed = false
local function run_diagnostic_probe()
    local lines = {}
    local function log_d(fmt, ...)
        local str = string.format(fmt, ...)
        table.insert(lines, str)
        print("[JHMCS-TRUTH] " .. str)
    end

    log_d("====================================================================")
    log_d("  AC8 TARGET TRACKING & OFF-SCREEN POSITION TRUTH PROBE (v15)")
    log_d("  Timestamp: %s", os.date("%Y-%m-%d %H:%M:%S"))
    log_d("====================================================================")
    log_d("")

    -- 1. Player Pawn
    local pawn = S.player_pawn or api:get_local_pawn(0)
    local p_loc = pawn and safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
    local p_rot = pawn and safe_call(function() return pawn:call("K2_GetActorRotation") end, nil)
    if pawn and p_loc and p_rot then
        log_d("PLAYER PAWN: %s", get_safe_name(pawn))
        log_d("  World Loc: (X=%.1f, Y=%.1f, Z=%.1f)", p_loc.X or 0, p_loc.Y or 0, p_loc.Z or 0)
        log_d("  Rotation : (Pitch=%.1f, Yaw=%.1f, Roll=%.1f)", p_rot.Pitch or 0, p_rot.Yaw or 0, p_rot.Roll or 0)
    else
        log_d("PLAYER PAWN: nil")
    end
    log_d("")

    local yaw_r = p_rot and math.rad(p_rot.Yaw or 0) or 0
    local cos_y = math.cos(yaw_r)
    local sin_y = math.sin(yaw_r)

    local function to_player_local(world_loc)
        if not p_loc or not world_loc then return 0, 0, 0, 0 end
        local dx = (world_loc.X or 0) - (p_loc.X or 0)
        local dy = (world_loc.Y or 0) - (p_loc.Y or 0)
        local dz = (world_loc.Z or 0) - (p_loc.Z or 0)
        local fwd   = dx * cos_y + dy * sin_y
        local right = -dx * sin_y + dy * cos_y
        local dist  = math.sqrt(dx*dx + dy*dy + dz*dz)
        return fwd / 100.0, right / 100.0, dz / 100.0, dist / 100.0
    end

    -- 2. Selected Target (from TargetSelectionComponent)
    local sel_comp = pawn and safe_call(function() return pawn.TargetSelection end, nil)
    local sel_target = nil
    if sel_comp then
        sel_target = safe_call(function() return sel_comp.SelectedTarget end, nil)
    end
    if not sel_comp and pawn then
        local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
        local comps = actor_comp_class and safe_call(function() return pawn:call("K2_GetComponentsByClass", actor_comp_class) end, {}) or {}
        for _, c in ipairs(comps) do
            local cname = get_safe_name(c)
            if cname:find("TargetSelection", 1, true) then
                sel_comp = c
                sel_target = safe_call(function() return c.SelectedTarget end, nil)
                break
            end
        end
    end

    log_d("=== LOCKED / SELECTED TARGET (REAL 3D AIRCRAFT IN SKY) ===")
    local st_loc = nil
    if sel_target then
        st_loc = safe_call(function() return sel_target:call("K2_GetActorLocation") end, nil)
        local fwd, right, up, dist = to_player_local(st_loc)
        local desc = (fwd >= 0) and "FRONT" or "*** REAR (BEHIND) ***"
        log_d("  Actor: %s", get_safe_name(sel_target))
        log_d("  World Loc: (X=%.1f, Y=%.1f, Z=%.1f)", st_loc and st_loc.X or 0, st_loc and st_loc.Y or 0, st_loc and st_loc.Z or 0)
        log_d("  Local Pos: Fwd=%.1fm, Right=%.1fm, Up=%.1fm | Total Dist=%.1fm | [%s]", fwd, right, up, dist, desc)
    else
        log_d("  SelectedTarget is nil")
    end
    log_d("")

    -- 3. All Enemy Pawns in Level
    log_d("=== ALL AIRCRAFT / TARGET PAWNS IN LEVEL ===")
    local pawn_class = api:find_uobject("Class /Script/Engine.Pawn")
    local all_pawns = pawn_class and safe_call(function() return pawn_class:get_objects_matching(false) end, {}) or {}
    local enemy_actors = {}
    for _, p in ipairs(all_pawns) do
        local pname = get_safe_name(p)
        if not pname:find("Default__", 1, true) and p ~= pawn then
            if pname:find("BP_OP", 1, true) or pname:find("uav", 1, true) or pname:find("Plane", 1, true) or pname:find("Enemy", 1, true) then
                table.insert(enemy_actors, p)
                local eloc = safe_call(function() return p:call("K2_GetActorLocation") end, nil)
                local fwd, right, up, dist = to_player_local(eloc)
                local desc = (fwd >= 0) and "FRONT" or "*** REAR ***"
                log_d("  Pawn [%02d] %s: Dist=%.0fm | Fwd=%.1fm, Right=%.1fm, Up=%.1fm | [%s]",
                    #enemy_actors, get_short_name(p), dist, fwd, right, up, desc)
            end
        end
    end
    log_d("  Total Enemy / Target Pawns: %d", #enemy_actors)
    log_d("")

    -- 4. Target Containers vs Real Target Comparison
    log_d("=== ACTIVE TARGET CONTAINERS VS REAL AIRCRAFT (ANTI-SUCTION COMPARISON) ===")
    for idx, ent in ipairs(S.containers) do
        local c_act = ent.obj
        if c_act then
            local cloc = safe_call(function() return c_act:call("K2_GetActorLocation") end, nil)
            local fwd, right, up, dist = to_player_local(cloc)
            local desc = (fwd >= 0) and "FRONT" or "*** REAR (BEHIND) ***"
            log_d("  Container [%02d] %s:", idx, ent.name)
            log_d("    World Loc: (X=%.1f, Y=%.1f, Z=%.1f)", cloc and cloc.X or 0, cloc and cloc.Y or 0, cloc and cloc.Z or 0)
            log_d("    Local Pos: Fwd=%.1fm, Right=%.1fm, Up=%.1fm, Dist=%.1fm | [%s]", fwd, right, up, dist, desc)

            if st_loc and cloc then
                local ddx = (cloc.X or 0) - (st_loc.X or 0)
                local ddy = (cloc.Y or 0) - (st_loc.Y or 0)
                local ddz = (cloc.Z or 0) - (st_loc.Z or 0)
                local delta_dist = math.sqrt(ddx*ddx + ddy*ddy + ddz*ddz) / 100.0
                log_d("    Delta vs SelectedTarget: %.1fm (dx=%.1fm, dy=%.1fm, dz=%.1fm)",
                    delta_dist, ddx/100.0, ddy/100.0, ddz/100.0)
                if delta_dist < 15.0 then
                    log_d("    ===> [STATUS: ON REAL TARGET] Container is physically matched to SelectedTarget aircraft!")
                else
                    log_d("    ===> [STATUS: DIVERGED / SUCTIONED] Container is %.1fm away from the actual plane!", delta_dist)
                end
            end
        end
    end
    log_d("")

    -- 5. True UClass Reflection
    local function reflect_class_and_instance(label, uobj)
        if not uobj then return end
        log_d("--------------------------------------------------------------------")
        log_d("  [REFLECTION] %s : %s", label, get_safe_name(uobj))
        log_d("--------------------------------------------------------------------")
        local cls = safe_call(function() return uobj:get_class() end, nil)
        local curr = cls
        local depth = 0
        local seen_props = {}
        local seen_funcs = {}

        while curr and depth < 6 do
            local cname = get_safe_name(curr)
            if cname:find("/Script/Engine.Actor", 1, true) or cname:find("/Script/CoreUObject", 1, true) then
                break
            end

            local ok_p, prop = pcall(function() return curr:get_child_properties() end)
            if ok_p and prop then
                while prop do
                    local ok_name, fn = pcall(function() return prop:get_fname():to_string() end)
                    if ok_name and fn and not seen_props[fn] then
                        seen_props[fn] = true
                        local ok_v, val = pcall(function() return uobj[fn] end)
                        if not ok_v or val == nil then
                            ok_v, val = pcall(function() return uobj:get_property(fn) end)
                        end
                        local val_str = tostring(val)
                        if type(val) == "userdata" then val_str = get_safe_name(val) end
                        log_d("    [PROP] %-32s = %s (%s)", fn, val_str, type(val))
                    end
                    local ok_next, next_p = pcall(function() return prop:get_next() end)
                    prop = (ok_next and next_p) or nil
                end
            end

            local ok_c, child = pcall(function() return curr:get_children() end)
            if ok_c and child then
                while child do
                    local ok_name, fn = pcall(function() return child:get_fname():to_string() end)
                    if ok_name and fn and not seen_funcs[fn] then
                        seen_funcs[fn] = true
                        log_d("    [FUNC] %s()", fn)
                    end
                    local ok_next, next_c = pcall(function() return child:get_next() end)
                    child = (ok_next and next_c) or nil
                end
            end

            curr = safe_call(function() return curr:get_super_struct() end, nil)
            depth = depth + 1
        end
        log_d("")
    end

    -- 1. LiveTargetContainerManager
    local mgr_class = api:find_uobject("Class /Script/Live.LiveTargetContainerManager")
    local mgr_inst = mgr_class and safe_call(function() return mgr_class:get_objects_matching(false)[1] end, nil)
    reflect_class_and_instance("LiveTargetContainerManager", mgr_inst)

    -- 2. First Container
    if #S.containers > 0 then
        reflect_class_and_instance("ChronicleTargetContainerActorBP (Slot 1)", S.containers[1].obj)
    end

    -- 3. LiveTargetSelectionComponent
    if sel_comp then
        reflect_class_and_instance("LiveTargetSelectionComponent", sel_comp)
    end

    -- Write output using relative paths (UEVR Sandbox compliant)
    local paths = {
        "data/ac8_target_tracking_truth.txt",
        "ac8_target_tracking_truth.txt"
    }
    for _, p in ipairs(paths) do
        local ok, f = pcall(function() return io.open(p, "w") end)
        if ok and f then
            f:write(table.concat(lines, "\n") .. "\n")
            f:close()
            break
        end
    end
    print("[JHMCS-TRUTH] Diagnostic log written to data/ac8_target_tracking_truth.txt")
end

--------------------------------------------------------------------------
-- 4. High-Speed Frame Loop & Native 350° FOV Enforcement
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan
    if #S.containers == 0 or (tick_count % 300 == 0) then
        scan_targets()
    end

    -- Auto-run truth probe at tick 60
    if tick_count == 60 or (tick_count > 60 and not probe_executed and S.player_pawn and #S.containers > 0) then
        probe_executed = true
        run_diagnostic_probe()
    end

    -- Native Engine FOV Expansion
    local pc = api:get_player_controller(0)
    if pc then
        local pcm = safe_call(function() return pc.PlayerCameraManager end, nil)
        if pcm then
            S.current_pcm_fov = safe_call(function() return pcm:call("GetFOVAngle") end, 0.0) or 0.0
        end

        if S.native_fov_enabled and S.native_fov > 0 then
            if math.abs(S.native_fov - S.applied_fov) > 0.1 or (tick_count % 60 == 0) then
                safe_call(function() pc:call("FOV", S.native_fov) end)
                if pcm then
                    safe_call(function() pcm:call("SetFOV", S.native_fov) end)
                    safe_call(function() pcm.DefaultFOV = S.native_fov end)
                end
                S.applied_fov = S.native_fov
            end
        elseif not S.native_fov_enabled and S.applied_fov > 0 then
            safe_call(function() pc:call("FOV", 0.0) end)
            S.applied_fov = -1.0
        end
    end

    local pawn = S.player_pawn
    if not pawn then return end

    local p_loc = safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
    local p_rot = safe_call(function() return pawn:call("K2_GetActorRotation") end, nil)
    if not p_loc or not p_rot then return end

    local p_x = p_loc.X or 0
    local p_y = p_loc.Y or 0
    local p_z = p_loc.Z or 0

    local yaw_r = math.rad(p_rot.Yaw or 0)
    local cos_y = math.cos(yaw_r)
    local sin_y = math.sin(yaw_r)

    -- Read live SelectedTarget for ImGui telemetry
    local sel_comp = safe_call(function() return pawn.TargetSelection end, nil)
    local sel_target = sel_comp and safe_call(function() return sel_comp.SelectedTarget end, nil)
    if sel_target then
        S.sel_target_name = get_short_name(sel_target)
        local st_loc = safe_call(function() return sel_target:call("K2_GetActorLocation") end, nil)
        if st_loc then
            local dx = (st_loc.X or 0) - p_x
            local dy = (st_loc.Y or 0) - p_y
            local dz = (st_loc.Z or 0) - p_z
            S.sel_target_fwd   = (dx * cos_y + dy * sin_y) / 100.0
            S.sel_target_right = (-dx * sin_y + dy * cos_y) / 100.0
            S.sel_target_up    = dz / 100.0
            S.sel_target_dist  = math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
        end
    else
        S.sel_target_name = "None"
        S.sel_target_dist = 0.0
    end

    local in_range_cnt = 0
    local wing_cnt     = 0
    local enemy_cnt    = 0
    local max_dist     = S.max_combat_dist_m
    local scale_dirty  = (math.abs(S.target_scale - S.applied_scale) > 0.005)

    for idx, entry in ipairs(S.containers) do
        local a = entry.obj
        if a then
            local a_loc = safe_call(function() return a:call("K2_GetActorLocation") end, nil)
            if a_loc then
                local dx = (a_loc.X or 0) - p_x
                local dy = (a_loc.Y or 0) - p_y
                local dz = (a_loc.Z or 0) - p_z
                local dist_sq = dx * dx + dy * dy + dz * dz
                local dist_m = math.floor(math.sqrt(dist_sq) / 100.0)
                entry.dist_m = dist_m

                -- Telemetry for container 1
                if idx == 1 then
                    S.cont1_fwd   = (dx * cos_y + dy * sin_y) / 100.0
                    S.cont1_right = (-dx * sin_y + dy * cos_y) / 100.0
                    S.cont1_up    = dz / 100.0
                    S.cont1_dist  = dist_m

                    if sel_target then
                        local st_loc = safe_call(function() return sel_target:call("K2_GetActorLocation") end, nil)
                        if st_loc then
                            local ddx = (a_loc.X or 0) - (st_loc.X or 0)
                            local ddy = (a_loc.Y or 0) - (st_loc.Y or 0)
                            local ddz = (a_loc.Z or 0) - (st_loc.Z or 0)
                            S.delta_dist = math.sqrt(ddx*ddx + ddy*ddy + ddz*ddz) / 100.0
                        end
                    else
                        S.delta_dist = -1.0
                    end
                end

                if dist_m > 5 and dist_m <= max_dist then
                    in_range_cnt = in_range_cnt + 1
                    if dist_m < 800 then
                        wing_cnt = wing_cnt + 1
                    else
                        enemy_cnt = enemy_cnt + 1
                    end

                    -- JHMCS Manual Override
                    if S.jhmcs_manual_override then
                        safe_call(function()
                            a:call("SetActorHiddenInGame", false)
                            a.bHiddenInGame = false
                        end)

                        local root = entry.root
                        if root then
                            safe_call(function()
                                root:call("SetVisibility", true)
                                root.bHiddenInGame = false
                            end)
                        end

                        for _, c in ipairs(entry.comps) do
                            safe_call(function()
                                c:call("SetVisibility", true)
                                c.bHiddenInGame = false
                            end)
                        end
                    end

                    -- Text Scaling
                    if scale_dirty then
                        for _, tc in ipairs({ entry.txt_dist, entry.txt_callsign, entry.txt_alliance }) do
                            if tc then
                                safe_call(function() tc:call("SetWorldSize", 26.0 * S.target_scale) end)
                                safe_call(function() tc:call("SetXScale", S.target_scale) end)
                                safe_call(function() tc:call("SetYScale", S.target_scale) end)
                            end
                        end
                    end
                end
            end
        end
    end

    if scale_dirty then
        S.applied_scale = S.target_scale
    end

    S.active_in_range = in_range_cnt
    S.wingman_count   = wing_cnt
    S.enemy_count     = enemy_cnt
end)

--------------------------------------------------------------------------
-- 5. Script UI (ImGui)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 NATIVE 350° FOV & TARGET TRUTH (" .. SCRIPT_VER .. ") ===")
    imgui.text_colored("Deep Reflection & Anti-Suction Analysis", 0xFF00FFCC)

    imgui.separator()

    -- 1. REAL-TIME TRACKING TRUTH TELEMETRY
    imgui.text_colored("--- Real-Time Target vs Container Telemetry ---", 0xFF00FFFF)
    imgui.text(string.format("Selected Target (Sky): %s", S.sel_target_name))
    if S.sel_target_dist > 0 then
        local pdesc = (S.sel_target_fwd >= 0) and "FRONT" or "BEHIND"
        imgui.text(string.format("  Real Plane Pos: Fwd=%.1fm, Right=%.1fm, Dist=%.0fm [%s]",
            S.sel_target_fwd, S.sel_target_right, S.sel_target_dist, pdesc))
    end

    if S.cont1_dist > 0 then
        local cdesc = (S.cont1_fwd >= 0) and "FRONT" or "BEHIND"
        imgui.text(string.format("  Container 1 Pos: Fwd=%.1fm, Right=%.1fm, Dist=%.0fm [%s]",
            S.cont1_fwd, S.cont1_right, S.cont1_dist, cdesc))
    end

    if S.delta_dist >= 0 then
        if S.delta_dist < 15.0 then
            imgui.text_colored(string.format("  State: [PERFECT 3D MATCH] Delta=%.1fm", S.delta_dist), 0xFF44FF44)
        else
            imgui.text_colored(string.format("  State: [SUCTIONED/DIVERGED!] Delta=%.1fm", S.delta_dist), 0xFFFF4444)
        end
    end

    imgui.separator()

    -- 2. NATIVE FOV EXPANSION
    imgui.text_colored("--- Native Engine FOV Setting ---", 0xFFFFFF00)
    imgui.text(string.format("Current Game Camera Readout: %.1f deg", S.current_pcm_fov))

    local chg_fe, val_fe = imgui.checkbox("Enable Native FOV Expansion##fov_en", S.native_fov_enabled)
    if chg_fe then S.native_fov_enabled = val_fe end

    if S.native_fov_enabled then
        local chg_fv, val_fv = imgui.slider_float("Target FOV Angle##fov_val", S.native_fov, 60.0, 350.0)
        if chg_fv then S.native_fov = val_fv end

        if imgui.button("Default (75°)##btn_f75") then S.native_fov = 75.0 end
        imgui.same_line()
        if imgui.button("Wide (120°)##btn_f120") then S.native_fov = 120.0 end
        imgui.same_line()
        if imgui.button("Half-Sphere (170°)##btn_f170") then S.native_fov = 170.0 end
        imgui.same_line()
        if imgui.button("Max (350°)##btn_f350") then S.native_fov = 350.0 end
    end

    imgui.separator()

    -- 3. JHMCS Manual Override Status
    local chg_mo, val_mo = imgui.checkbox("Manual JHMCS Component Override##man_jhmcs", S.jhmcs_manual_override)
    if chg_mo then S.jhmcs_manual_override = val_mo end

    imgui.separator()

    -- Live Status Counters
    imgui.text(string.format("Tracked Slots in Memory: %d", S.total_slots))
    imgui.text_colored(string.format("Active in Combat Range:  %d targets", S.active_in_range), 0xFF44FF44)
    imgui.same_line()
    imgui.text_disabled(string.format("(Near: %d, Far: %d)", S.wingman_count, S.enemy_count))

    imgui.separator()

    -- Marker Scaling
    imgui.text("Target Marker Size:")
    local chg_sc, val_sc = imgui.slider_float("Marker Scale##m_scale", S.target_scale, 0.5, 3.0)
    if chg_sc then S.target_scale = val_sc end

    imgui.separator()

    if imgui.button("Run Truth Diagnostic Probe Now##btn_truth_probe") then
        probe_executed = false
        run_diagnostic_probe()
    end
    imgui.same_line()
    if imgui.button("Rescan Containers##btn_rescan") then
        scan_targets()
    end
end

-- Initial scan
scan_targets()

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully (%s).", SCRIPT_NAME, SCRIPT_VER))
