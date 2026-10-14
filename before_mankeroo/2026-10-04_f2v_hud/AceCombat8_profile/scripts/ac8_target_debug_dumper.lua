--[[
  ============================================================================
  ac8_target_debug_dumper.lua : Comprehensive Target Marker Diagnostics & Dump
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Purpose:    Investigate why Target Marker scaling had no visual effect.
              Performs deep inspection across 4 distinct layers:
                Layer 1: UMG Widget tree (all Target/Marker/Lock/Reticle widgets)
                Layer 2: Player Pawn & Component properties (FocusTarget, FCS, etc.)
                Layer 3: Locked Enemy Actor components (WidgetComponent, Billboards)
                Layer 4: 3D HUD Materials & Cockpit Render Targets (MID parameters)
              Plus:
                Interactive "Blink / Hide Test" to verify if the widget is the
                actual visual element rendered on screen.
  Output:     data/ac8_target_deep_dump.txt
  UI:         Simple English for Japanese VR users.
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-TGT-DUMP"
local DUMP_FILE   = "data/ac8_target_deep_dump.txt"

local dump_file_handle = nil
local function open_dump()
    local ok, f = pcall(function() return io.open(DUMP_FILE, "w") end)
    if ok and f then
        dump_file_handle = f
        return true
    end
    return false
end

local function dlog(fmt, ...)
    local str = string.format(fmt, ...)
    print(string.format("[%s] %s", SCRIPT_NAME, str))
    if dump_file_handle then
        pcall(function()
            dump_file_handle:write(str .. "\n")
            dump_file_handle:flush()
        end)
    end
end

local function close_dump()
    if dump_file_handle then
        pcall(function() dump_file_handle:close() end)
        dump_file_handle = nil
    end
end

local function get_safe_name(obj)
    if not obj then return "nil" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or tostring(obj)
end

local function get_safe_class_name(obj)
    if not obj then return "nil" end
    local ok, c = pcall(function() return obj:get_class():get_name() end)
    return (ok and type(c) == "string") and c or "unknown"
end

--------------------------------------------------------------------------
-- 1. LAYER 1: Deep UMG Widget Inspection
--------------------------------------------------------------------------
local function dump_umg_widgets()
    dlog("====================================================================")
    dlog("  LAYER 1: UMG WIDGET TREE & TARGET WIDGET CANDIDATES")
    dlog("====================================================================")

    local umg_class = api:find_uobject("Class /Script/UMG.Widget")
    if not umg_class then
        dlog("  [ERROR] Class /Script/UMG.Widget not found!")
        return
    end

    local all_widgets = {}
    local ok, objs = pcall(function() return umg_class:get_objects_matching(false) end)
    if ok and type(objs) == "table" then all_widgets = objs end
    dlog(string.format("  Total UWidgets in memory: %d", #all_widgets))

    -- Target-related keywords
    local KEYWORDS = {
        "target", "marker", "locator", "lock", "reticle", "sight", "cursor",
        "container", "aim", "tracking", "seeker", "box", "enemy", "crosshair"
    }

    local matched = {}
    for _, w in ipairs(all_widgets) do
        local fn = get_safe_name(w):lower()
        if fn:find("/engine/transient", 1, true) then
            for _, kw in ipairs(KEYWORDS) do
                if fn:find(kw, 1, true) then
                    table.insert(matched, w)
                    break
                end
            end
        end
    end

    dlog(string.format("  Transient Target-related Widgets found: %d\n", #matched))

    for idx, w in ipairs(matched) do
        local fn   = get_safe_name(w)
        local cn   = get_safe_class_name(w)
        local vis  = "err"
        local invp = "err"
        local parent_fn = "none"

        pcall(function() vis = tostring(w:call("GetVisibility")) end)
        pcall(function() invp = tostring(w:call("IsInViewport")) end)
        pcall(function()
            local p = w:call("GetParent")
            if p then parent_fn = get_safe_name(p):match("([^.]+)$") or get_safe_name(p) end
        end)

        -- Geometry and Transform
        local sz_x, sz_y = "n/a", "n/a"
        pcall(function()
            local ds = w:call("GetDesiredSize")
            if ds then sz_x, sz_y = tostring(ds.X), tostring(ds.Y) end
        end)

        local rt_sx, rt_sy = "1.0", "1.0"
        local rt_tx, rt_ty = "0", "0"
        pcall(function()
            local rt = w:get_property("RenderTransform")
            if rt then
                if rt.Scale then rt_sx, rt_sy = tostring(rt.Scale.X), tostring(rt.Scale.Y) end
                if rt.Translation then rt_tx, rt_ty = tostring(rt.Translation.X), tostring(rt.Translation.Y) end
            end
        end)

        -- Slot info
        local slot_info = "none"
        pcall(function()
            local slot = w.Slot or w:call("Slot")
            if slot then
                local scn = get_safe_class_name(slot)
                slot_info = scn
                if slot.GetSize then
                    local ssz = slot:call("GetSize")
                    if ssz then slot_info = slot_info .. string.format("(Size: %.1f, %.1f)", ssz.X or 0, ssz.Y or 0) end
                end
            end
        end)

        local short_name = fn:match("([^.]+)$") or fn
        dlog(string.format("  [%03d] %s", idx, short_name))
        dlog(string.format("        Class: %s | Vis: %s | InViewport: %s | Parent: %s", cn, vis, invp, parent_fn))
        dlog(string.format("        DesiredSize: (%s, %s) | RenderScale: (%s, %s) | Translation: (%s, %s)", sz_x, sz_y, rt_sx, rt_sy, rt_tx, rt_ty))
        dlog(string.format("        Slot: %s", slot_info))
        dlog(string.format("        FullName: %s", fn))
        dlog("")
    end
end

--------------------------------------------------------------------------
-- 2. LAYER 2: Player Pawn & Targeting Components
--------------------------------------------------------------------------
local function dump_player_components()
    dlog("====================================================================")
    dlog("  LAYER 2: PLAYER PAWN & TARGETING COMPONENTS")
    dlog("====================================================================")

    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    if not pawn then
        dlog("  [WARN] Player Pawn not found (Not in flight?)")
        return nil
    end

    dlog(string.format("  Player Pawn: %s", get_safe_name(pawn)))
    dlog(string.format("  Class: %s", get_safe_class_name(pawn)))

    -- Inspect PlayerController & AHUD
    local pc = api:get_player_controller(0)
    if pc then
        dlog(string.format("  PlayerController: %s", get_safe_name(pc)))
        local my_hud = pc.MyHUD
        if my_hud then
            dlog(string.format("  ★ PlayerController.MyHUD (AHUD): %s", get_safe_name(my_hud)))
            pcall(function() dlog(string.format("        bShowHUD = %s", tostring(my_hud.bShowHUD))) end)
        else
            dlog("  PlayerController.MyHUD is nil")
        end
    end

    -- Get all components on Pawn
    local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    local comps = {}
    if actor_comp_class then
        local ok, c_list = pcall(function() return pawn:call("K2_GetComponentsByClass", actor_comp_class) end)
        if ok and type(c_list) == "table" then comps = c_list end
    end

    dlog(string.format("  Total Components on Pawn: %d", #comps))

    local target_actor = nil
    for idx, c in ipairs(comps) do
        local cfn = get_safe_name(c)
        local short = cfn:match("([^.]+)$") or cfn
        dlog(string.format("  * Pawn Component [%02d]: %s", idx, short))

        -- Probe targeting properties
        for _, prop in ipairs({ "FocusTarget", "OverrideFocusTarget", "CurrentTarget", "SelectedTarget",
                                "TargetActor", "LockedTarget", "LockOnRange", "LockOnAngle",
                                "MarkerSize", "BoxSize", "TargetBoxSize", "TargetScale", "ReticleScale" }) do
            pcall(function()
                local val = c[prop]
                if val ~= nil then
                    dlog(string.format("        -> Property '%s' = %s", prop, get_safe_name(val)))
                    if prop:find("Target", 1, true) and type(val) ~= "number" and type(val) ~= "string" and type(val) ~= "boolean" then
                        target_actor = val
                    end
                end
            end)
        end
    end

    return target_actor
end

--------------------------------------------------------------------------
-- 3. LAYER 3: Target Enemy Actor & Its Components (Full Component Dump)
--------------------------------------------------------------------------
local function dump_target_actor(target_actor)
    dlog("====================================================================")
    dlog("  LAYER 3: LOCKED ENEMY ACTOR & ALL 3D COMPONENTS")
    dlog("====================================================================")

    if not target_actor then
        dlog("  [INFO] No Target Actor currently locked on.")
        dlog("  (Tip: Lock onto an enemy in-game before running dump to inspect enemy components)")
        return
    end

    dlog(string.format("  Current Target Actor: %s", get_safe_name(target_actor)))

    local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    if actor_comp_class then
        local comps = target_actor:call("K2_GetComponentsByClass", actor_comp_class) or {}
        dlog(string.format("  Target Actor ALL Components count: %d", #comps))
        for idx, c in ipairs(comps) do
            local fn = get_safe_name(c)
            local short = fn:match("([^.]+)$") or fn
            dlog(string.format("  * Target Component [%02d]: %s", idx, short))
            pcall(function()
                if c.GetWidget then
                    local w = c:call("GetWidget")
                    dlog(string.format("        -> Internal Widget: %s", get_safe_name(w)))
                end
            end)
        end
    end
end

--------------------------------------------------------------------------
-- 4. LAYER 4: 3D HUD Actors & Cockpit Dynamic Materials (MID)
--------------------------------------------------------------------------
local function dump_hud_actors_and_materials()
    dlog("====================================================================")
    dlog("  LAYER 4: COCKPIT HUD ACTORS & DYNAMIC MATERIALS (MID)")
    dlog("====================================================================")

    -- Check LiveMainHUDParent4K
    local hud_parent_class = api:find_uobject("Class /Game/Blueprints/UI/WBP/HUD4K/Common/LiveMainHUDParent4K.LiveMainHUDParent4K_C")
    if hud_parent_class then
        local hud_actors = hud_parent_class:get_objects_matching(false) or {}
        dlog(string.format("  LiveMainHUDParent4K instances: %d", #hud_actors))
        for idx, a in ipairs(hud_actors) do
            dlog(string.format("    [%02d] %s", idx, get_safe_name(a)))
        end
    else
        dlog("  LiveMainHUDParent4K class not found directly.")
    end

    -- Check Cockpit Mesh Materials
    local pawn = api:get_local_pawn(0)
    if pawn then
        local mesh_class = api:find_uobject("Class /Script/Engine.MeshComponent")
        if mesh_class then
            local meshes = pawn:call("K2_GetComponentsByClass", mesh_class) or {}
            for _, m in ipairs(meshes) do
                local mfn = get_safe_name(m):lower()
                if mfn:find("cockpit", 1, true) or mfn:find("hud", 1, true) or mfn:find("glass", 1, true) then
                    dlog(string.format("  Cockpit Mesh: %s", get_safe_name(m)))
                    local num_mats = 0
                    pcall(function() num_mats = m:call("GetNumMaterials") or 0 end)
                    for midx = 0, num_mats - 1 do
                        local mat = nil
                        pcall(function() mat = m:call("GetMaterial", midx) end)
                        if mat then
                            dlog(string.format("    Material [%d]: %s (Class: %s)", midx, get_safe_name(mat), get_safe_class_name(mat)))
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- MASTER DEEP DUMP TRIGGER
--------------------------------------------------------------------------
local last_dump_status = "Not executed yet"

local function run_master_dump()
    if not open_dump() then
        last_dump_status = "Error: Failed to open dump file"
        return
    end

    dlog("====================================================================")
    dlog(string.format("  ACE COMBAT 8 - TARGET MARKER COMPREHENSIVE DIAGNOSTIC"))
    dlog(string.format("  Time: %s", os.date("%Y-%m-%d %H:%M:%S")))
    dlog("====================================================================\n")

    pcall(dump_umg_widgets)
    dlog("\n")

    local tgt_actor = nil
    pcall(function() tgt_actor = dump_player_components() end)
    dlog("\n")

    pcall(function() dump_target_actor(tgt_actor) end)
    dlog("\n")

    pcall(dump_hud_actors_and_materials)
    dlog("\n")

    dlog("====================================================================")
    dlog("  DIAGNOSTIC COMPLETE")
    dlog("====================================================================")

    close_dump()
    last_dump_status = "Dump completed to " .. DUMP_FILE
    print(string.format("[%s] Deep dump finished successfully!", SCRIPT_NAME))
end

--------------------------------------------------------------------------
-- INTERACTIVE VISUAL TESTS (Blink / Hide / Flash Tests)
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- INTERACTIVE VISUAL TESTS (Layer Isolation Tests)
--------------------------------------------------------------------------
local test_state = {
    hide_target_draw = false,
    hide_seeker      = false,
    hide_locator     = false,
    hide_waypoint       = false,
    hide_dynamic_cv     = false,
    hide_main_hud       = false,
    hide_other_roots    = false,
    disable_target_comp = false,
    hide_cockpit_glass  = false,
    hide_ahud           = false,
    
    widgets_cache = {},
    other_root_widgets = {},
    target_comps = {},
    cockpit_meshes = {},
}

local function find_widgets_by_pat(pat)
    local umg_class = api:find_uobject("Class /Script/UMG.Widget")
    if not umg_class then return {} end
    local objs = umg_class:get_objects_matching(false) or {}
    local out = {}
    for _, w in ipairs(objs) do
        local fn = get_safe_name(w)
        if fn:find("/Engine/Transient", 1, true) and fn:find(pat, 1, true) then
            table.insert(out, w)
        end
    end
    return out
end

local flash_timer = 0

local function apply_vis_test(key, pat, hide_flag)
    if not test_state.widgets_cache[key] or (flash_timer % 60 == 0) then
        test_state.widgets_cache[key] = find_widgets_by_pat(pat)
    end
    local vis_code = hide_flag and 1 or 4 -- 1 = Collapsed (Hide), 4 = SelfHitTestInvisible (Show)
    for _, w in ipairs(test_state.widgets_cache[key] or {}) do
        pcall(function() w:call("SetVisibility", vis_code) end)
    end
end

-- TEST 6: Other Root Widgets
local function apply_other_roots(hide_flag)
    local uw_class = api:find_uobject("Class /Script/UMG.UserWidget")
    if not uw_class then return end
    local objs = uw_class:get_objects_matching(false) or {}
    local vis_code = hide_flag and 1 or 0
    for _, w in ipairs(objs) do
        local fn = get_safe_name(w)
        if fn:find("/Engine/Transient", 1, true) and not fn:find("MainFlight", 1, true) then
            local inv = false
            pcall(function() inv = w:call("IsInViewport") end)
            if inv then
                pcall(function() w:call("SetVisibility", vis_code) end)
            end
        end
    end
end

-- TEST 7: TargetSelection Component
local function apply_target_comp(disable_flag)
    local pawn = api:get_local_pawn(0)
    if not pawn then return end
    local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    if not actor_comp_class then return end
    local comps = pawn:call("K2_GetComponentsByClass", actor_comp_class) or {}
    for _, c in ipairs(comps) do
        local fn = get_safe_name(c):lower()
        if fn:find("target", 1, true) or fn:find("focus", 1, true) then
            pcall(function()
                c:call("SetComponentTickEnabled", not disable_flag)
                c:call("SetVisibility", not disable_flag)
                c.bHiddenInGame = disable_flag
            end)
        end
    end
end

-- TEST 8: Cockpit Mesh
local function apply_cockpit_mesh(hide_flag)
    local pawn = api:get_local_pawn(0)
    if not pawn then return end
    local mesh_class = api:find_uobject("Class /Script/Engine.MeshComponent")
    if not mesh_class then return end
    local meshes = pawn:call("K2_GetComponentsByClass", mesh_class) or {}
    for _, m in ipairs(meshes) do
        local fn = get_safe_name(m):lower()
        if fn:find("cockpit", 1, true) or fn:find("hud", 1, true) or fn:find("glass", 1, true) then
            pcall(function() m:call("SetVisibility", not hide_flag) end)
        end
    end
end

-- TEST 9: PlayerController.MyHUD (AHUD)
local function apply_ahud(hide_flag)
    local pc = api:get_player_controller(0)
    if pc and pc.MyHUD then
        pcall(function() pc.MyHUD.bShowHUD = not hide_flag end)
    end
end

uevr.sdk.callbacks.on_post_engine_tick(function()
    flash_timer = flash_timer + 1

    if test_state.hide_target_draw then apply_vis_test("tgt_draw", "TargetSelectionDraw", true) end
    if test_state.hide_seeker      then apply_vis_test("seeker", "SeekerWidget", true) end
    if test_state.hide_locator     then apply_vis_test("locator", "Locator", true) end
    if test_state.hide_waypoint    then apply_vis_test("waypoint", "Container_WayPoint", true) end
    if test_state.hide_dynamic_cv  then apply_vis_test("dyn_cv", "DynamicDrawCanvas", true) end
    if test_state.hide_main_hud    then apply_vis_test("main_hud", "MainFlight", true) end
    if test_state.hide_other_roots then apply_other_roots(true) end
    if test_state.disable_target_comp then apply_target_comp(true) end
    if test_state.hide_cockpit_glass  then apply_cockpit_mesh(true) end
    if test_state.hide_ahud           then apply_ahud(true) end
end)

--------------------------------------------------------------------------
-- Script UI (ImGui) - Simple English for Japanese VR Users
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Diagnostic & Dumper (v4) ===")
    imgui.text("Facts: 2D HUD (MainFlight + Other Roots) is NOT where marker lives.")

    imgui.separator()

    -- Action Button
    if imgui.button("RUN DEEP DUMP (Save data/ac8_target_deep_dump.txt)") then
        run_master_dump()
    end
    imgui.same_line()
    imgui.text("Dump Status: " .. last_dump_status)

    imgui.separator()

    -- Advanced Pipeline Isolation Tests
    imgui.text("--- Pipeline Isolation Tests (Find Where Marker Lives) ---")

    -- Test 8: Cockpit HUD Glass 3D Mesh
    local cg, vg = imgui.checkbox("TEST 8: HIDE Cockpit Mesh (HUD Glass & Interior 3D Mesh)", test_state.hide_cockpit_glass)
    if cg then
        test_state.hide_cockpit_glass = vg
        if not vg then apply_cockpit_mesh(false) end
    end
    imgui.text(" *If TEST 8 hides marker -> Marker is on Cockpit 3D HUD Glass Material")

    -- Test 9: AHUD (Legacy Canvas Draw)
    local ca, va = imgui.checkbox("TEST 9: HIDE AHUD (Legacy Canvas bShowHUD = false)", test_state.hide_ahud)
    if ca then
        test_state.hide_ahud = va
        if not va then apply_ahud(false) end
    end
    imgui.text(" *If TEST 9 hides marker -> Marker is drawn by C++ AHUD Canvas")

    -- Test 7 (Recap): TargetSelection Component
    local ct, vt = imgui.checkbox("TEST 7: DISABLE TargetSelection Component", test_state.disable_target_comp)
    if ct then
        test_state.disable_target_comp = vt
        if not vt then apply_target_comp(false) end
    end

    -- Test 5 (Recap)
    local cm, vm = imgui.checkbox("TEST 5: HIDE MainFlight 2D HUD", test_state.hide_main_hud)
    if cm then
        test_state.hide_main_hud = vm
        if not vm then apply_vis_test("main_hud", "MainFlight", false) end
    end

    imgui.separator()
    if imgui.button("RESET ALL TESTS (Restore Everything)") then
        test_state.hide_target_draw = false
        test_state.hide_seeker      = false
        test_state.hide_locator     = false
        test_state.hide_waypoint    = false
        test_state.hide_dynamic_cv  = false
        test_state.hide_main_hud    = false
        test_state.hide_other_roots = false
        test_state.disable_target_comp = false
        test_state.hide_cockpit_glass  = false
        test_state.hide_ahud           = false
        apply_vis_test("tgt_draw", "TargetSelectionDraw", false)
        apply_vis_test("seeker", "SeekerWidget", false)
        apply_vis_test("locator", "Locator", false)
        apply_vis_test("waypoint", "Container_WayPoint", false)
        apply_vis_test("dyn_cv", "DynamicDrawCanvas", false)
        apply_vis_test("main_hud", "MainFlight", false)
        apply_other_roots(false)
        apply_target_comp(false)
        apply_cockpit_mesh(false)
        apply_ahud(false)
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
