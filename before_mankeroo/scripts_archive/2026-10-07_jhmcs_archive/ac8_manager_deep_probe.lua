--[[
  ============================================================================
  ac8_manager_deep_probe.lua : Deep Inspection of Native HUD & Container Manager
  ============================================================================
  Inspects all native fields, properties, and functions of:
  - LiveTargetContainerManager
  - LiveMainHUDParent4K
  - ChronicleTargetContainerActorBP
  - TargetSelection / Seeker / HUD classes
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

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

local dump_lines = {}
local function log_l(fmt, ...)
    local str = string.format(fmt, ...)
    table.insert(dump_lines, str)
    print("[MGR-PROBE] " .. str)
end

local function dump_all_properties_of_class(uclass_obj, instance_obj, label)
    log_l("=== CLASS PROBE: %s (%s) ===", label, get_safe_name(uclass_obj))
    if not uclass_obj then return end

    -- Probe functions on class
    local fn_list = {}
    local curr_fn = safe_call(function() return uclass_obj.Children end, nil)
    -- Also search via Function matching
    local func_class = api:find_uobject("Class /Script/CoreUObject.Function")
    local all_funcs = func_class and func_class:get_objects_matching(false) or {}
    local cname = get_short_name(uclass_obj)
    for _, fn in ipairs(all_funcs) do
        local fname = get_safe_name(fn)
        if fname:find(cname, 1, true) then
            table.insert(fn_list, get_short_name(fn))
        end
    end
    table.sort(fn_list)
    log_l("  Functions (%d): %s", #fn_list, table.concat(fn_list, ", "))

    -- Probe properties by scanning property names from common UE / flight patterns
    local prop_candidates = {
        -- FOV, Angles & Ranges
        "FieldOfView", "FOV", "Fov", "ViewAngle", "Angle", "MaxAngle", "MinAngle", "ConeAngle",
        "TargetConeAngle", "LockOnAngle", "SeekerAngle", "RadarAngle", "BoresightAngle",
        "TrackingAngle", "OffBoresightAngle", "MaxOffBoresightAngle", "DetectionAngle",
        "ScreenAngle", "LimitAngle", "GimbalLimit", "GimbalAngle", "MaxGimbalAngle",
        "ViewDistance", "MaxDistance", "MinDistance", "CullDistance", "MaxDrawDistance",
        "DrawDistance", "VisibleDistance", "LockOnDistance", "MaxLockOnDistance",
        "TargetDistance", "Range", "MaxRange", "DetectionRange", "RadarRange",
        -- Screen & Bounds
        "ScreenMargin", "ScreenBounds", "ScreenExtent", "ScreenRadius", "ScreenRect",
        "Margin", "Padding", "Border", "ViewportMargin", "EdgeMargin",
        "bEnableOffscreenTarget", "bOffscreenTarget", "bClampToScreen", "bClampToViewport",
        "bClamp", "bUseScreenSpace", "bScreenSpace", "bIsScreenSpace", "bProjection",
        -- Scaling & Sizing
        "Scale", "TargetScale", "BoxScale", "MarkerScale", "IconScale", "Size", "TargetSize",
        "BoxSize", "MarkerSize", "DefaultSize", "DrawSize", "BaseSize", "Extent",
        -- Targets & Containers
        "TargetContainers", "ActiveContainers", "ContainerActors", "Containers", "Targets",
        "ActiveTargets", "TargetActors", "TargetList", "LockedTarget", "SelectedTarget",
        "CurrentTarget", "PrimaryTarget", "LockTarget", "TrackingTargets",
        "ContainerPool", "ActorPool", "Pool", "MaxContainers", "MaxTargets",
        -- Flags
        "bEnabled", "bVisible", "bActive", "bHidden", "bEnableJHMCS", "bJHMCS",
        "bIsVR", "bVREnabled", "bEnableVR", "bHMD", "bHeadTracking",
        -- Cameras & Controllers
        "PlayerCamera", "CameraManager", "PlayerController", "PlayerPawn", "HUDParent",
        "TargetContainerManager", "ContainerManager", "SelectionComponent"
    }

    if instance_obj then
        log_l("--- Properties on Instance: %s ---", get_safe_name(instance_obj))
        for _, p in ipairs(prop_candidates) do
            local ok, val = pcall(function() return instance_obj[p] end)
            if not ok or val == nil then
                ok, val = pcall(function() return instance_obj:get_property(p) end)
            end
            if ok and val ~= nil then
                local vstr = tostring(val)
                if type(val) == "userdata" then vstr = get_safe_name(val) end
                log_l("  [PROP] %-26s = %s (%s)", p, vstr, type(val))
            end
        end
    end
    log_l("")
end

local function run_deep_probe()
    dump_lines = {}
    log_l("====================================================================")
    log_l("  AC8 NATIVE HUD & TARGET MANAGER DEEP PROBE")
    log_l("  Timestamp: %s", os.date("%Y-%m-%d %H:%M:%S"))
    log_l("====================================================================")
    log_l("")

    -- 1. LiveTargetContainerManager
    local mgr_class = api:find_uobject("Class /Script/Live.LiveTargetContainerManager")
    local mgr_inst = mgr_class and safe_call(function() return mgr_class:get_objects_matching(false)[1] end, nil)
    dump_all_properties_of_class(mgr_class, mgr_inst, "LiveTargetContainerManager")

    -- 2. LiveMainHUDParent4K
    local hud_class = api:find_uobject("BlueprintGeneratedClass /Game/UI/Material/HUD/LiveMainHUDParent4K.LiveMainHUDParent4K_C")
                   or api:find_uobject("Class /Script/Live.LiveMainHUDParentActor")
    local hud_inst = hud_class and safe_call(function() return hud_class:get_objects_matching(false)[1] end, nil)
    dump_all_properties_of_class(hud_class, hud_inst, "LiveMainHUDParent4K")

    -- 3. LiveTargetContainerActor / ChronicleTargetContainerActorBP
    local cont_class = api:find_uobject("BlueprintGeneratedClass /Game/UI/Material/HUD/TargetContainer3DUI/ChronicleTargetContainerActorBP.ChronicleTargetContainerActorBP_C")
                    or api:find_uobject("Class /Script/Live.LiveTargetContainerActor")
    local cont_inst = cont_class and safe_call(function() return cont_class:get_objects_matching(false)[1] end, nil)
    dump_all_properties_of_class(cont_class, cont_inst, "ChronicleTargetContainerActorBP")

    -- 4. Target Selection / Seeker Components in Engine
    local comp_class = api:find_uobject("Class /Script/CoreUObject.Class")
    local all_classes = comp_class and comp_class:get_objects_matching(false) or {}
    local targeting_classes = {}
    for _, cls in ipairs(all_classes) do
        local cname = get_safe_name(cls)
        if (cname:find("TargetSelection", 1, true) or cname:find("TargetManager", 1, true) or cname:find("Seeker", 1, true) or cname:find("JHMCS", 1, true) or cname:find("LiveHUD", 1, true) or cname:find("ChronicleHUD", 1, true))
           and not cname:find("Default__", 1, true) then
            table.insert(targeting_classes, cls)
        end
    end
    log_l("=== ALL RELEVANT TARGETING / HUD CLASSES IN MEMORY (%d) ===", #targeting_classes)
    for _, tc in ipairs(targeting_classes) do
        log_l("  Class: %s", get_safe_name(tc))
    end
    log_l("")

    -- 5. Inspect Player Pawn's Components (Is there a Seeker / TargetSelectionComponent?)
    local pawn = api:get_local_pawn(0)
    if pawn then
        log_l("=== PLAYER PAWN COMPONENT PROBE: %s ===", get_safe_name(pawn))
        local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
        local p_comps = actor_comp_class and safe_call(function() return pawn:call("K2_GetComponentsByClass", actor_comp_class) end, {}) or {}
        for _, pc in ipairs(p_comps) do
            local pname = get_safe_name(pc)
            if pname:find("Target", 1, true) or pname:find("HUD", 1, true) or pname:find("Weapon", 1, true) or pname:find("Seeker", 1, true) or pname:find("Lock", 1, true) or pname:find("Camera", 1, true) then
                log_l("  Component: %s", pname)
                dump_all_properties_of_class(pc:get_class(), pc, get_short_name(pc))
            end
        end
    end

    -- Write to disk
    local out_path = "C:\\Users\\Ogaki\\AppData\\Roaming\\UnrealVRMod\\AceCombat8\\data\\ac8_manager_deep_probe.txt"
    local f = io.open(out_path, "w")
    if f then
        f:write(table.concat(dump_lines, "\n"))
        f:close()
    end
    local out_path2 = "D:\\Ogaki\\Desktop\\Ace-uevr-test\\data\\ac8_manager_deep_probe.txt"
    local f2 = io.open(out_path2, "w")
    if f2 then
        f2:write(table.concat(dump_lines, "\n"))
        f2:close()
    end
    print("[MGR-PROBE] Deep probe completed. Written to: " .. out_path)
end

-- Run once on script load
run_deep_probe()

-- Add UI button to rerun anytime
if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        if imgui.button("Run Manager Deep Probe Now##btn_probe") then
            run_deep_probe()
        end
    end)
end
