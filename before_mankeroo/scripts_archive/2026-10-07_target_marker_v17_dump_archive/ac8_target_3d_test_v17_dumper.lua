--[[
  ============================================================================
  ac8_target_3d_test.lua : Target Marker Scaler & Deep Parameter Dumper (v17)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Purpose:    [1] DEEP PARAMETER DUMPER:
                  Dumps all manipulatable properties, variables, functions,
                  and materials of ChronicleTargetContainerActorBP_C,
                  ContainerBox (UMaterialBillboardComponent), and
                  LiveTargetContainerManager to:
                  data/ac8_target_parameters_dump.txt
              [2] TEST A: Verified Text Scaling (1.0x ~ 5.0x)
              [3] TEST B: Reticle Frame Testing (Atomic 1-Control per Case)
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-TGT-V17"

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

local function safe_write_file(basename, content)
    local written_paths = {}
    local candidate_paths = {
        "C:\\Users\\Ogaki\\AppData\\Roaming\\UnrealVRMod\\AceCombat8\\data\\" .. basename,
        "D:\\Ogaki\\Desktop\\Ace-uevr-test\\data\\" .. basename,
        "data/" .. basename,
        basename
    }
    for _, p in ipairs(candidate_paths) do
        local ok, f = pcall(function() return io.open(p, "w") end)
        if ok and f then
            pcall(function()
                f:write(content)
                f:flush()
                f:close()
            end)
            print(string.format("[%s] Successfully wrote file: %s", SCRIPT_NAME, p))
            table.insert(written_paths, p)
        end
    end
    return (#written_paths > 0) and written_paths[1] or nil
end

--------------------------------------------------------------------------
-- 1. State Table
--------------------------------------------------------------------------
local S = {
    player_pawn          = nil,
    containers           = {},
    active_tab           = 2,

    dump_done            = false,
    dump_status          = "Not dumped yet",

    -- TEST A: Text Scaling
    test_a = {
        master_scale     = 1.0,
        distance_scale   = 1.0,
        model_scale      = 1.0,
        alliance_scale   = 1.0,

        orig_world_sizes = {},
        orig_x_scales    = {},
        orig_y_scales    = {},
    },

    -- TEST B: Reticle Frame
    test_b = {
        target_idx            = 1,

        -- Part B-1: Component Isolation (Verified Reference)
        hide_container_box    = false,
        hide_root_comp        = false,
        hide_all_text         = false,
        hide_entire_actor     = false,

        -- Part B-2: Scaling Methods
        b2_1_add_element_size = 128.0,
        b2_2_mid_scale        = 1.0,
        b2_3_mid_size         = 128.0,
        b2_4_mid_uv_scale     = 1.0,
        b2_5_bp_box_size      = 128.0,
        b2_6_mgr_scale        = 1.0,
        b2_7_screen_space_off = false,

        last_injected_size    = 0.0,
    }
}

--------------------------------------------------------------------------
-- 2. Material Helper
--------------------------------------------------------------------------
local cached_target_mat = nil

local function get_container_box_material(cb)
    if cached_target_mat then return cached_target_mat end

    if cb then
        local ok, m = pcall(function() return cb:call("GetMaterial", 0) end)
        if ok and m ~= nil then
            cached_target_mat = m
            return m
        end

        ok, m = pcall(function() return cb.Material end)
        if ok and m ~= nil then
            cached_target_mat = m
            return m
        end
    end

    local mat_class = api:find_uobject("Class /Script/Engine.MaterialInterface")
    if mat_class then
        local mats = mat_class:get_objects_matching(false) or {}
        for _, mat in ipairs(mats) do
            local fn = get_safe_name(mat)
            if fn:find("TargetContainer3DUI", 1, true) and not fn:find("Default__", 1, true) then
                cached_target_mat = mat
                return mat
            end
        end
        for _, mat in ipairs(mats) do
            local fn = get_safe_name(mat)
            if (fn:find("TargetBox", 1, true) or fn:find("TargetMarker", 1, true)) and not fn:find("Default__", 1, true) then
                cached_target_mat = mat
                return mat
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------
-- 3. EXHAUSTIVE DEEP PARAMETER DUMPER
--------------------------------------------------------------------------
local function dump_all_target_parameters()
    local lines = {}
    local function log_l(fmt, ...)
        local str = string.format(fmt, ...)
        table.insert(lines, str)
        print(string.format("[%s] %s", SCRIPT_NAME, str))
    end

    log_l("====================================================================")
    log_l("  ACE COMBAT 8 - TARGET MARKER EXHAUSTIVE PARAMETER & ARCHITECTURE DUMP")
    log_l("  Time: %s", os.date("%Y-%m-%d %H:%M:%S"))
    log_l("====================================================================")
    log_l("")

    -- Helper to probe property dictionary
    local function probe_dict(label, obj, prop_list)
        if not obj then return end
        log_l("--- [%s] Property Scan: %s ---", label, get_safe_name(obj))
        local found_count = 0
        for _, p in ipairs(prop_list) do
            local val = nil
            local ok = false
            -- 1. Direct index
            ok, val = pcall(function() return obj[p] end)
            -- 2. get_property
            if not ok or val == nil then
                ok, val = pcall(function() return obj:get_property(p) end)
            end

            if ok and val ~= nil then
                found_count = found_count + 1
                local val_str = "nil"
                if type(val) == "userdata" then
                    val_str = get_safe_name(val)
                elseif type(val) == "table" then
                    local t_items = {}
                    for k, v in pairs(val) do table.insert(t_items, string.format("%s=%s", tostring(k), tostring(v))) end
                    val_str = "{" .. table.concat(t_items, ", ") .. "}"
                else
                    val_str = tostring(val)
                end
                log_l("  [PROP] %-28s = %-30s (type: %s)", p, val_str, type(val))
            end
        end
        if found_count == 0 then
            log_l("  (No properties matched in probed dictionary)")
        end
        log_l("")
    end

    -- Candidate property dictionaries
    local candidate_actor_props = {
        -- Components
        "ContainerBox", "EscortBillboardImage", "AntiClockTargetPinBillboardImage", "ClockTargetPinBillboardImage",
        "AllianceText", "DistanceText", "ObjectTypeText", "ObjectCallsignText", "GamerTagText", "NextTargetText",
        "RootComponent",
        -- Sizes & Scales
        "TargetSize", "MarkerSize", "BoxSize", "TargetBoxSize", "FrameSize", "ReticleSize",
        "DefaultSize", "CurrentSize", "DrawSize", "BaseSize", "Size", "Extent", "Radius",
        "Scale", "BoxScale", "MarkerScale", "TargetScale", "IconScale", "ReticleScale",
        "ScreenSize", "Width", "Height", "LockOnBoxSize", "TargetMarkerSize",
        -- Colors & Visibility
        "TargetColor", "BoxColor", "ReticleColor", "DefaultColor", "Opacity", "Alpha",
        "bHiddenInGame", "bVisible",
        -- Targeting & Gameplay State
        "TargetActor", "TargetComponent", "SelectedTarget", "TargetSelection",
        "TargetType", "Alliance", "Callsign", "Distance", "Angle", "State",
        "IsLockedOn", "IsTarget", "IsTracked", "IsPrimary", "IsCurrentTarget",
        -- Manager & Parents
        "TargetContainerManager", "HUDParent", "Manager", "TargetManager", "ContainerManager"
    }

    local candidate_comp_props = {
        "Elements", "Sprite", "Material", "Materials", "OverrideMaterials",
        "BaseSizeX", "BaseSizeY", "SizeX", "SizeY", "Size", "Width", "Height",
        "bSizeIsInScreenSpace", "DistanceToSizeCurve", "DistanceToOpacityCurve",
        "ScreenSize", "ScreenSizeMin", "ScreenSizeMax", "MinDistance", "MaxDistance",
        "Scale", "RelativeScale3D", "ComponentScale", "WorldScale3D",
        "Opacity", "Color", "BoxSize", "MarkerSize", "FrameSize", "ReticleSize",
        "BoundsScale", "OpacityMaskRefVal", "Texture", "DynamicMaterial",
        "bHiddenInGame", "bVisible", "RelativeLocation", "RelativeRotation",
        "AttachParent", "AttachSocketName", "Mobility"
    }

    local candidate_mgr_props = {
        "TargetContainers", "ActiveContainers", "ContainerActors", "TargetActors", "Containers",
        "TargetSize", "MarkerSize", "BoxSize", "TargetBoxSize", "FrameSize", "ReticleSize",
        "Scale", "TargetScale", "IconScale", "BoxScale", "MarkerScale", "ReticleScale",
        "ContainerClass", "TargetContainerClass", "ChronicleTargetContainerActorBP",
        "FieldOfView", "MaxDistance", "MinDistance", "CullDistance", "LockOnDistance",
        "DefaultBoxSize", "TargetBoxExtent", "BoxExtent", "TargetExtent",
        "HUDParent", "PlayerPawn", "PlayerController"
    }

    -- 1. Active Target Containers
    log_l("【1. ACTIVE TARGET CONTAINER ACTORS IN LEVEL (Total: %d)】", #S.containers)
    for idx, ent in ipairs(S.containers) do
        local act = ent.obj
        log_l("--------------------------------------------------------------------")
        log_l("  TARGET [%02d] : %s", idx, get_safe_name(act))
        log_l("  Distance    : %d meters", ent.dist_m)
        log_l("  Class       : %s", get_safe_name(act:get_class()))

        -- Components List
        log_l("  Components  (Total: %d):", #ent.comps)
        for c_idx, c_info in ipairs(ent.comps) do
            local c = c_info.obj
            local loc = safe_call(function() return c.RelativeLocation end, nil)
            local loc_str = loc and string.format("(X=%.1f, Y=%.1f, Z=%.1f)", loc.X or 0, loc.Y or 0, loc.Z or 0) or "nil"
            local sc = safe_call(function() return c.RelativeScale3D end, nil)
            local sc_str = sc and string.format("(X=%.2f, Y=%.2f, Z=%.2f)", sc.X or 0, sc.Y or 0, sc.Z or 0) or "nil"
            local vis = safe_call(function() return c.bVisible end, nil)
            local hid = safe_call(function() return c.bHiddenInGame end, nil)
            log_l("    [%02d] %-30s | Class: %-26s | RelLoc: %s | Scale: %s | Vis=%s, Hid=%s",
                c_idx, c_info.name, c_info.class, loc_str, sc_str, tostring(vis), tostring(hid))
        end

        -- Scan Target Actor Properties
        probe_dict("Active_TargetActor_" .. idx, act, candidate_actor_props)

        -- If Target 1, deep probe ContainerBox
        if idx == 1 and act.ContainerBox then
            local cb = act.ContainerBox
            log_l(">>> TARGET 1 CONTAINERBOX DEEP PROBE <<<")
            probe_dict("Active_ContainerBox", cb, candidate_comp_props)

            -- Function calls on ContainerBox
            local n_mat = safe_call(function() return cb:call("GetNumMaterials") end, -1)
            log_l("    cb:GetNumMaterials() = %s", tostring(n_mat))
            for m_idx = 0, 3 do
                local m = safe_call(function() return cb:call("GetMaterial", m_idx) end, nil)
                if m then
                    log_l("    cb:GetMaterial(%d)   = %s", m_idx, get_safe_name(m))
                end
            end
            local mat_resolved = get_container_box_material(cb)
            log_l("    Resolved Material   = %s", get_safe_name(mat_resolved))
            log_l("")
        end
    end
    log_l("")

    -- 2. CDO of ChronicleTargetContainerActorBP_C
    local cdo_bp = api:find_uobject("ChronicleTargetContainerActorBP_C /Game/UI/Material/HUD/TargetContainer3DUI/ChronicleTargetContainerActorBP.Default__ChronicleTargetContainerActorBP_C")
    if cdo_bp then
        log_l("【2. CDO OF ChronicleTargetContainerActorBP_C】")
        probe_dict("CDO_ChronicleTargetActor", cdo_bp, candidate_actor_props)
        if cdo_bp.ContainerBox then
            probe_dict("CDO_ContainerBox", cdo_bp.ContainerBox, candidate_comp_props)
        end
    end
    log_l("")

    -- 3. CDO of LiveTargetContainerActor (C++ Base Class)
    local cdo_cpp = api:find_uobject("LiveTargetContainerActor /Script/Live.Default__LiveTargetContainerActor")
    if cdo_cpp then
        log_l("【3. CDO OF LiveTargetContainerActor (C++ BASE)】")
        probe_dict("CDO_LiveTargetContainerActor", cdo_cpp, candidate_actor_props)
        if cdo_cpp.ContainerBox then
            probe_dict("CDO_CPP_ContainerBox", cdo_cpp.ContainerBox, candidate_comp_props)
        end
    end
    log_l("")

    -- 4. LiveTargetContainerManager
    local mgr_class = api:find_uobject("Class /Script/Live.LiveTargetContainerManager")
    local mgr_objs = mgr_class and mgr_class:get_objects_matching(false) or {}
    log_l("【4. LiveTargetContainerManager INSTANCES (Total: %d)】", #mgr_objs)
    for idx, mgr in ipairs(mgr_objs) do
        log_l("  [%02d] %s (Outer: %s)", idx, get_safe_name(mgr), get_safe_name(mgr:get_outer()))
        probe_dict("Manager_" .. idx, mgr, candidate_mgr_props)
    end
    log_l("")

    -- 5. LiveMainHUDParent4K Actors
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    local all_actors = actor_class and actor_class:get_objects_matching(false) or {}
    local hud_parents = {}
    for _, a in ipairs(all_actors) do
        local fn = get_safe_name(a)
        if fn:find("LiveMainHUDParent4K", 1, true) and not fn:find("Default__", 1, true) then
            table.insert(hud_parents, a)
        end
    end
    log_l("【5. LiveMainHUDParent4K ACTORS (Total: %d)】", #hud_parents)
    for idx, hud in ipairs(hud_parents) do
        log_l("  [%02d] %s", idx, get_safe_name(hud))
        probe_dict("HUDParent_" .. idx, hud, {
            "TargetContainerManager", "TargetManager", "HUDManager", "TargetSelection",
            "Scale", "HUDScale", "ReticleScale"
        })
    end
    log_l("")

    -- 6. All UFunctions matching Target/Container/Billboard/Chronicle
    local func_class = api:find_uobject("Class /Script/CoreUObject.Function")
    local all_funcs = func_class and func_class:get_objects_matching(false) or {}
    local matched_funcs = {}
    for _, fn in ipairs(all_funcs) do
        local fn_name = get_safe_name(fn)
        if fn_name:find("TargetContainer", 1, true)
           or fn_name:find("ChronicleTarget", 1, true)
           or fn_name:find("ContainerBox", 1, true)
           or fn_name:find("MaterialBillboard", 1, true)
           or (fn_name:find("LiveTarget", 1, true) and not fn_name:find("LiveTargetSelectionComponent", 1, true)) then
            table.insert(matched_funcs, fn_name)
        end
    end
    table.sort(matched_funcs)
    log_l("【6. RELEVANT UFUNCTIONS IN ENGINE MEMORY (Total: %d)】", #matched_funcs)
    for idx, fn_name in ipairs(matched_funcs) do
        log_l("  [%02d] %s", idx, fn_name)
    end
    log_l("")

    -- 7. All Materials & Material Instances matching Target/Container/Box/Reticle
    local mat_class = api:find_uobject("Class /Script/Engine.MaterialInterface")
    local all_mats = mat_class and mat_class:get_objects_matching(false) or {}
    local matched_mats = {}
    for _, m in ipairs(all_mats) do
        local m_name = get_safe_name(m)
        if (m_name:find("TargetContainer", 1, true)
            or m_name:find("TargetBox", 1, true)
            or m_name:find("TargetMarker", 1, true)
            or m_name:find("Reticle", 1, true)
            or m_name:find("TargetPin", 1, true)
            or m_name:find("Container3D", 1, true))
           and not m_name:find("Default__", 1, true) then
            table.insert(matched_mats, m)
        end
    end
    log_l("【7. RELEVANT MATERIALS IN ENGINE MEMORY (Total: %d)】", #matched_mats)
    for idx, m in ipairs(matched_mats) do
        log_l("  [%02d] %s", idx, get_safe_name(m))
        -- Probe scalar parameters
        for _, p_name in ipairs({ "Scale", "Size", "IconScale", "BoxSize", "UVScale", "Tiling", "Thickness", "Opacity" }) do
            local v = safe_call(function() return m:call("GetScalarParameterDefaultValue", p_name) end, nil)
            if v ~= nil then
                log_l("       Param '%s' = %s", p_name, tostring(v))
            end
        end
    end
    log_l("")

    log_l("====================================================================")
    log_l("  PARAMETER & ARCHITECTURE DUMP COMPLETE")
    log_l("====================================================================")

    local p = safe_write_file("ac8_target_parameters_dump.txt", table.concat(lines, "\n"))
    S.dump_status = p and ("Saved to " .. p) or "Failed"
    S.dump_done = true
end

--------------------------------------------------------------------------
-- 4. Scanner for Target Containers in Sky
--------------------------------------------------------------------------
local function scan_containers()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    S.player_pawn = pawn

    local p_loc = nil
    if pawn then pcall(function() p_loc = pawn:call("K2_GetActorLocation") end) end

    local function calc_dist(a)
        if not (p_loc and a) then return 0 end
        local a_loc = nil
        pcall(function() a_loc = a:call("K2_GetActorLocation") end)
        if not a_loc then return 0 end
        local dx = (a_loc.X or a_loc.x or 0) - (p_loc.X or p_loc.x or 0)
        local dy = (a_loc.Y or a_loc.y or 0) - (p_loc.Y or p_loc.y or 0)
        local dz = (a_loc.Z or a_loc.z or 0) - (p_loc.Z or p_loc.z or 0)
        return math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) / 100.0)
    end

    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    local all_actors = actor_class and actor_class:get_objects_matching(false) or {}

    local comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    local found = {}

    for _, a in ipairs(all_actors) do
        local fn = get_safe_name(a)
        if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
            local comps = {}
            if comp_class then
                local raw_comps = a:call("K2_GetComponentsByClass", comp_class) or {}
                for _, c in ipairs(raw_comps) do
                    table.insert(comps, {
                        obj   = c,
                        name  = get_short_name(c),
                        class = get_short_name(c:get_class()),
                        full  = get_safe_name(c)
                    })
                end
            end

            local att_actors = safe_call(function()
                local res = {}
                a:call("GetAttachedActors", res)
                return res
            end, {}) or {}

            table.insert(found, {
                obj        = a,
                name       = get_short_name(a),
                dist_m     = calc_dist(a),
                comps      = comps,
                att_actors = att_actors
            })
        end
    end

    S.containers = found

    -- Trigger dump once targets are found
    if #S.containers > 0 and not S.dump_done then
        dump_all_target_parameters()
    end
end

--------------------------------------------------------------------------
-- 5. TEST A: Text Scaling Execution (Phase 1 EngineTick - Lightest)
--------------------------------------------------------------------------
local function apply_test_a_texts()
    local m_sc = S.test_a.master_scale
    if math.abs(m_sc - 1.0) < 0.005
       and math.abs(S.test_a.distance_scale - 1.0) < 0.005
       and math.abs(S.test_a.model_scale - 1.0) < 0.005
       and math.abs(S.test_a.alliance_scale - 1.0) < 0.005 then
        return
    end

    for _, entry in ipairs(S.containers) do
        local a = entry.obj
        if a then
            for _, comp_info in ipairs(entry.comps) do
                local c = comp_info.obj
                local c_name = comp_info.name

                local sc = nil
                if c_name:find("DistanceText", 1, true) then
                    sc = m_sc * S.test_a.distance_scale
                elseif c_name:find("ObjectType", 1, true) or c_name:find("Callsign", 1, true) then
                    sc = m_sc * S.test_a.model_scale
                elseif c_name:find("AllianceText", 1, true) or c_name:find("NextTarget", 1, true) or c_name:find("GamerTag", 1, true) then
                    sc = m_sc * S.test_a.alliance_scale
                elseif c_name:find("Text", 1, true) then
                    sc = m_sc
                end

                if sc and sc > 0 then
                    pcall(function() c:call("SetRelativeScale3D", { X = sc, Y = sc, Z = sc }) end)
                    pcall(function() c.RelativeScale3D = { X = sc, Y = sc, Z = sc } end)
                    pcall(function() c:call("SetWorldScale3D", { X = sc, Y = sc, Z = sc }) end)

                    pcall(function()
                        local ws = c.WorldSize
                        if ws and type(ws) == "number" then
                            local full = comp_info.full
                            if not S.test_a.orig_world_sizes[full] then S.test_a.orig_world_sizes[full] = ws end
                            c.WorldSize = S.test_a.orig_world_sizes[full] * sc
                            c:call("SetWorldSize", S.test_a.orig_world_sizes[full] * sc)
                        end
                    end)

                    pcall(function()
                        local xs = c.XScale
                        local ys = c.YScale
                        if xs and type(xs) == "number" then
                            local full = comp_info.full
                            if not S.test_a.orig_x_scales[full] then
                                S.test_a.orig_x_scales[full] = xs
                                S.test_a.orig_y_scales[full] = ys or xs
                            end
                            c.XScale = S.test_a.orig_x_scales[full] * sc
                            c.YScale = S.test_a.orig_y_scales[full] * sc
                            c:call("SetXScale", S.test_a.orig_x_scales[full] * sc)
                            c:call("SetYScale", S.test_a.orig_y_scales[full] * sc)
                        end
                    end)
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- 6. TEST B: Reticle Frame Execution
--------------------------------------------------------------------------
local function get_test_b_target_entries()
    if S.test_b.target_idx == 0 then
        return S.containers
    else
        local ent = S.containers[S.test_b.target_idx]
        return ent and { ent } or {}
    end
end

local function robust_hide_comp(comp)
    if not comp then return end
    pcall(function() comp:call("SetVisibility", false, true) end)
    pcall(function() comp:call("SetHiddenInGame", true, true) end)
    pcall(function() comp.bHiddenInGame = true end)
    pcall(function() comp.bVisible = false end)
    pcall(function() comp:call("Deactivate") end)
end

local function apply_test_b_frame()
    local entries = get_test_b_target_entries()

    for _, entry in ipairs(entries) do
        local a = entry.obj
        if a then
            if S.test_b.hide_entire_actor then
                pcall(function() a:call("SetActorHiddenInGame", true) end)
                pcall(function() a.bHiddenInGame = true end)
            end

            if a.RootComponent and S.test_b.hide_root_comp then
                robust_hide_comp(a.RootComponent)
            end

            if math.abs(S.test_b.b2_5_bp_box_size - 128.0) > 1.0 then
                local bsz = S.test_b.b2_5_bp_box_size
                pcall(function() a.BoxSize = bsz end)
                pcall(function() a.TargetBoxSize = bsz end)
                pcall(function() a.MarkerSize = bsz end)
                pcall(function() a.Size = bsz end)
            end

            for _, comp_info in ipairs(entry.comps) do
                local c = comp_info.obj
                local c_name = comp_info.name

                if c_name == "ContainerBox" and S.test_b.hide_container_box then
                    robust_hide_comp(c)
                elseif c_name:find("Text", 1, true) and S.test_b.hide_all_text then
                    robust_hide_comp(c)
                end

                if c_name == "ContainerBox" then
                    if math.abs(S.test_b.b2_1_add_element_size - S.test_b.last_injected_size) > 1.0 then
                        local bsz = S.test_b.b2_1_add_element_size
                        local mat = get_container_box_material(c)
                        if mat then
                            pcall(function() c:call("AddElement", mat, nil, true, bsz, bsz, nil) end)
                            pcall(function() c:call("MarkRenderStateDirty") end)
                        end
                        S.test_b.last_injected_size = bsz
                    end

                    if math.abs(S.test_b.b2_2_mid_scale - 1.0) > 0.01 then
                        local sc = S.test_b.b2_2_mid_scale
                        pcall(function()
                            local mat = get_container_box_material(c)
                            local mid = c:call("CreateAndSetMaterialInstanceDynamicFromMaterial", 0, mat)
                                        or c:call("CreateAndSetMaterialInstanceDynamic", 0)
                            if mid then
                                mid:call("SetScalarParameterValue", "Scale", sc)
                                mid:call("SetScalarParameterValue", "IconScale", sc)
                                mid:call("SetScalarParameterValue", "ReticleScale", sc)
                            end
                        end)
                    end

                    if math.abs(S.test_b.b2_3_mid_size - 128.0) > 1.0 then
                        local sz = S.test_b.b2_3_mid_size
                        pcall(function()
                            local mat = get_container_box_material(c)
                            local mid = c:call("CreateAndSetMaterialInstanceDynamicFromMaterial", 0, mat)
                                        or c:call("CreateAndSetMaterialInstanceDynamic", 0)
                            if mid then
                                mid:call("SetScalarParameterValue", "Size", sz)
                                mid:call("SetScalarParameterValue", "IconSize", sz)
                                mid:call("SetScalarParameterValue", "BoxSize", sz)
                            end
                        end)
                    end

                    if math.abs(S.test_b.b2_4_mid_uv_scale - 1.0) > 0.01 then
                        local uv = S.test_b.b2_4_mid_uv_scale
                        pcall(function()
                            local mat = get_container_box_material(c)
                            local mid = c:call("CreateAndSetMaterialInstanceDynamicFromMaterial", 0, mat)
                                        or c:call("CreateAndSetMaterialInstanceDynamic", 0)
                            if mid then
                                mid:call("SetScalarParameterValue", "UVScale", uv)
                                mid:call("SetScalarParameterValue", "Tiling", uv)
                                mid:call("SetScalarParameterValue", "Zoom", uv)
                            end
                        end)
                    end

                    if S.test_b.b2_7_screen_space_off then
                        pcall(function() c.bSizeIsInScreenSpace = false end)
                    end
                end
            end
        end
    end

    if math.abs(S.test_b.b2_6_mgr_scale - 1.0) > 0.01 then
        local ms = S.test_b.b2_6_mgr_scale
        local mgr_class = api:find_uobject("Class /Script/Live.LiveTargetContainerManager")
        local mgr_objs = mgr_class and mgr_class:get_objects_matching(false) or {}
        for _, mgr in ipairs(mgr_objs) do
            pcall(function() mgr.TargetScale = ms end)
            pcall(function() mgr.Scale = ms end)
            pcall(function() mgr.TargetSize = 128.0 * ms end)
        end
    end
end

--------------------------------------------------------------------------
-- 7. Continuous Execution Across Render Phases
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1
    if tick_count % 60 == 0 then
        scan_containers()
    end

    apply_test_a_texts()
    apply_test_b_frame()
end)

if uevr.sdk.callbacks.on_post_calculate_stereo_view_offset ~= nil then
    uevr.sdk.callbacks.on_post_calculate_stereo_view_offset(function()
        apply_test_a_texts()
        apply_test_b_frame()
    end)
end

if uevr.sdk.callbacks.on_pre_slate_draw_window_render_thread ~= nil then
    uevr.sdk.callbacks.on_pre_slate_draw_window_render_thread(function()
        apply_test_a_texts()
        apply_test_b_frame()
    end)
end

--------------------------------------------------------------------------
-- 8. Script UI
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Marker Scaler (v17) : Test A & Test B ===")
    imgui.text_colored(string.format("Target Aircraft in Sky: %d", #S.containers), 0xFF00FFCC)

    imgui.same_line()
    if imgui.button("Rescan Targets##rescan") then scan_containers() end

    -- PROMINENT DUMP BUTTON
    imgui.same_line()
    if imgui.button(">> DUMP ALL TARGET PARAMETERS NOW <<##dump_btn") then
        dump_all_target_parameters()
    end
    imgui.text_colored(string.format("Dump Status: %s", S.dump_status), 0xFFFFAA00)

    -- Tab Switcher
    if imgui.button("=== [TEST A] Target Text Scaler (Verified) ===") then S.active_tab = 1 end
    imgui.same_line()
    if imgui.button("=== [TEST B] Reticle Frame Investigation (1-Control Cases) ===") then S.active_tab = 2 end

    imgui.separator()

    -- ====================================================================
    -- [TAB 1] TEST A: Verified Text Scaler
    -- ====================================================================
    if S.active_tab == 1 then
        imgui.text_colored("--- TEST A: Target Text Scaler (Phase 1 EngineTick - Lightest) ---", 0xFFFFFF00)
        imgui.text("Front & 360° Text Scaling is confirmed 100% working.")

        local c_m, v_m = imgui.slider_float("ALL Texts Master Scale##a_mst", S.test_a.master_scale, 0.5, 5.0)
        if c_m then S.test_a.master_scale = v_m end

        if imgui.button("1.0x (Default)##a_1") then S.test_a.master_scale = 1.0 end
        imgui.same_line()
        if imgui.button("1.5x##a_15") then S.test_a.master_scale = 1.5 end
        imgui.same_line()
        if imgui.button("2.0x##a_2") then S.test_a.master_scale = 2.0 end
        imgui.same_line()
        if imgui.button("3.0x##a_3") then S.test_a.master_scale = 3.0 end

        imgui.separator()

        imgui.text("Individual Text Sliders:")
        local c_d, v_d = imgui.slider_float("Distance Numbers (DistanceText)##a_dst", S.test_a.distance_scale, 0.5, 3.0)
        if c_d then S.test_a.distance_scale = v_d end
        imgui.same_line()
        if imgui.button("1.0x##a_rd") then S.test_a.distance_scale = 1.0 end

        local c_mod, v_mod = imgui.slider_float("Aircraft Model (ObjectType)##a_mod", S.test_a.model_scale, 0.5, 3.0)
        if c_mod then S.test_a.model_scale = v_mod end
        imgui.same_line()
        if imgui.button("1.0x##a_rm") then S.test_a.model_scale = 1.0 end

        local c_al, v_al = imgui.slider_float("Alliance & TGT (AllianceText)##a_ali", S.test_a.alliance_scale, 0.5, 3.0)
        if c_al then S.test_a.alliance_scale = v_al end
        imgui.same_line()
        if imgui.button("1.0x##a_ra") then S.test_a.alliance_scale = 1.0 end

    -- ====================================================================
    -- [TAB 2] TEST B: Reticle Frame (1 Test Case = 1 Control!)
    -- ====================================================================
    elseif S.active_tab == 2 then
        imgui.text_colored("--- TEST B: Reticle Frame Investigation (1 Control per Case) ---", 0xFF00FFFF)

        local c_tidx, v_tidx = imgui.slider_int("Target Aircraft##b_tgt", S.test_b.target_idx, 0, math.max(1, #S.containers))
        if c_tidx then S.test_b.target_idx = v_tidx end
        imgui.same_line()
        imgui.text(S.test_b.target_idx == 0 and "(All Targets in Sky)" or string.format("(Target %d only)", S.test_b.target_idx))

        imgui.separator()

        -- PART B-1: COMPONENT ISOLATION (SOLVED & VERIFIED REFERENCE)
        imgui.text_colored("[Part B-1: Component Isolation (VERIFIED: B1-1 is the square!)]", 0xFF00FF88)

        local c_hcb, v_hcb = imgui.checkbox("Case B1-1: Hide ContainerBox only (Verified Square!)##h_cb", S.test_b.hide_container_box)
        if c_hcb then S.test_b.hide_container_box = v_hcb end

        local c_hrc, v_hrc = imgui.checkbox("Case B1-5: Hide RootComponent only##h_rc", S.test_b.hide_root_comp)
        if c_hrc then S.test_b.hide_root_comp = v_hrc end

        local c_ht, v_ht = imgui.checkbox("Case B1-7: Hide All Texts only (Distance, Model, TGT)##h_tx", S.test_b.hide_all_text)
        if c_ht then S.test_b.hide_all_text = v_ht end

        local c_ha, v_ha = imgui.checkbox("Case B1-8: Hide Entire Actor (ChronicleTargetContainerActorBP)##h_act", S.test_b.hide_entire_actor)
        if c_ha then S.test_b.hide_entire_actor = v_ha end

        if imgui.button("Uncheck All (Show Everything)##b1_uncheck") then
            S.test_b.hide_container_box = false
            S.test_b.hide_root_comp     = false
            S.test_b.hide_all_text      = false
            S.test_b.hide_entire_actor  = false
        end

        imgui.separator()

        -- PART B-2: BILLBOARD SCALING METHODS
        imgui.text_colored("[Part B-2: Billboard Scaling Methods - 1 Control per Case]", 0xFFFFAA00)

        local c1_c, c1_v = imgui.slider_float("Case B2-1: AddElement BaseSize (64~1024)##c1", S.test_b.b2_1_add_element_size, 64.0, 1024.0)
        if c1_c then S.test_b.b2_1_add_element_size = c1_v end
        imgui.same_line()
        if imgui.button("128 Reset##rst_c1") then S.test_b.b2_1_add_element_size = 128.0 end

        local c2_c, c2_v = imgui.slider_float("Case B2-2: Billboard Material MID 'Scale'##c2", S.test_b.b2_2_mid_scale, 0.1, 5.0)
        if c2_c then S.test_b.b2_2_mid_scale = c2_v end
        imgui.same_line()
        if imgui.button("1.0 Reset##rst_c2") then S.test_b.b2_2_mid_scale = 1.0 end

        local c3_c, c3_v = imgui.slider_float("Case B2-3: Billboard Material MID 'Size'##c3", S.test_b.b2_3_mid_size, 10.0, 1000.0)
        if c3_c then S.test_b.b2_3_mid_size = c3_v end
        imgui.same_line()
        if imgui.button("128 Reset##rst_c3") then S.test_b.b2_3_mid_size = 128.0 end

        local c4_c, c4_v = imgui.slider_float("Case B2-4: Billboard Material MID 'UVScale'##c4", S.test_b.b2_4_mid_uv_scale, 0.1, 5.0)
        if c4_c then S.test_b.b2_4_mid_uv_scale = c4_v end
        imgui.same_line()
        if imgui.button("1.0 Reset##rst_c4") then S.test_b.b2_4_mid_uv_scale = 1.0 end

        local c5_c, c5_v = imgui.slider_float("Case B2-5: Blueprint Variable 'TargetBoxSize'##c5", S.test_b.b2_5_bp_box_size, 32.0, 512.0)
        if c5_c then S.test_b.b2_5_bp_box_size = c5_v end
        imgui.same_line()
        if imgui.button("128 Reset##rst_c5") then S.test_b.b2_5_bp_box_size = 128.0 end

        local c6_c, c6_v = imgui.slider_float("Case B2-6: TargetContainerManager 'TargetScale'##c6", S.test_b.b2_6_mgr_scale, 0.2, 5.0)
        if c6_c then S.test_b.b2_6_mgr_scale = c6_v end
        imgui.same_line()
        if imgui.button("1.0 Reset##rst_c6") then S.test_b.b2_6_mgr_scale = 1.0 end

        local c7_chk, c7_v = imgui.checkbox("Case B2-7: ScreenSpace Mode Off (Force WorldSpace)##c7", S.test_b.b2_7_screen_space_off)
        if c7_chk then S.test_b.b2_7_screen_space_off = c7_v end

        imgui.separator()

        if imgui.button("=== Reset All B2 Sliders to Default ===") then
            S.test_b.b2_1_add_element_size = 128.0
            S.test_b.b2_2_mid_scale        = 1.0
            S.test_b.b2_3_mid_size         = 128.0
            S.test_b.b2_4_mid_uv_scale     = 1.0
            S.test_b.b2_5_bp_box_size      = 128.0
            S.test_b.b2_6_mgr_scale        = 1.0
            S.test_b.b2_7_screen_space_off = false
        end
    end
end

-- Initial scan & dump
scan_containers()
dump_all_target_parameters()

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
