--[[
  ============================================================================
  ac8_target_3d_test.lua : Target Container Deep Inspector & Scaler (v9)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Purpose:    Deep inspection and scaling of ChronicleTargetContainerActorBP_C:
              - Automatically dumps complete component & property structure
              - Tests Actor Scale, Component Relative/World Scale, Billboard BaseSize,
                ChildActors, and Material Scalar Parameters
              - Individual & Multi-target control with live distance display
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-TGT-DEEP"
local DUMP_FILE   = "d:/Ogaki/Desktop/Ace-uevr-test/data/ac8_target_container_deep_dump.txt"

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
    player_pawn      = nil,
    containers       = {}, -- list of container info tables
    container_states = {}, -- idx -> { hidden = bool, scale = float, comp_scales = {} }

    master_hidden    = false,
    master_scale     = 1.0,

    -- Material parameter experiment
    mat_param_name   = "Scale",
    mat_param_val    = 1.0,

    -- Aerial refuel UI
    aerial_actor     = nil,
    aerial_name      = "None",
    aerial_hidden    = false,

    dump_written     = false,
    last_dump_time   = "Never",
}

--------------------------------------------------------------------------
-- 2. Deep Diagnostic Dump (Automatic)
--------------------------------------------------------------------------
local function dump_container_structure(container)
    local ok, f = pcall(function() return io.open(DUMP_FILE, "w") end)
    if not (ok and f) then return end

    f:write("====================================================================\n")
    f:write("  CHRONICLE TARGET CONTAINER DEEP ARCHITECTURE DUMP\n")
    f:write("  Time: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    f:write("  Actor: " .. get_safe_name(container) .. "\n")
    local c_class = container:get_class()
    f:write("  Class: " .. get_safe_name(c_class) .. "\n")
    f:write("====================================================================\n\n")

    -- 1. All Components
    local comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    local comps = comp_class and container:call("K2_GetComponentsByClass", comp_class) or {}
    f:write(string.format("【COMPONENTS IN TARGET CONTAINER (Total: %d)】\n", #comps))
    for idx, c in ipairs(comps) do
        local comp_class_obj = c:get_class()
        f:write(string.format("  [%02d] %s\n", idx, get_short_name(c)))
        f:write(string.format("       Class: %s\n", get_safe_name(comp_class_obj)))
        f:write(string.format("       FullName: %s\n", get_safe_name(c)))

        -- Relative Scale
        pcall(function()
            local sc = c.RelativeScale3D
            if sc then
                f:write(string.format("       * RelativeScale3D: (%.3f, %.3f, %.3f)\n", sc.X or sc.x or 1, sc.Y or sc.y or 1, sc.Z or sc.z or 1))
            end
        end)

        -- World Scale
        pcall(function()
            local wsc = c:call("K2_GetComponentScale")
            if wsc then
                f:write(string.format("       * ComponentScale: (%.3f, %.3f, %.3f)\n", wsc.X or wsc.x or 1, wsc.Y or wsc.y or 1, wsc.Z or wsc.z or 1))
            end
        end)

        -- Child Actor
        pcall(function()
            local ca = c.ChildActor
            if ca then
                f:write(string.format("       * ChildActor: %s (Class: %s)\n", get_safe_name(ca), get_safe_name(ca:get_class())))
            end
        end)

        -- Material Billboard Elements
        pcall(function()
            local elems = c.Elements
            if elems then
                f:write(string.format("       * MaterialBillboard Elements (type=%s):\n", type(elems)))
                if type(elems) == "table" then
                    for el_idx, el in ipairs(elems) do
                        f:write(string.format("         [%d] BaseSize=(%s, %s) Mat=%s\n", el_idx, tostring(el.BaseSizeX), tostring(el.BaseSizeY), get_safe_name(el.Material)))
                    end
                end
            end
        end)

        -- BillboardComponent Sprite
        pcall(function()
            local sp = c.Sprite
            if sp then f:write(string.format("       * Billboard Sprite: %s\n", get_safe_name(sp))) end
            local ss = c.ScreenSize
            if ss then f:write(string.format("       * Billboard ScreenSize: %s\n", tostring(ss))) end
        end)

        -- Instanced Static Mesh
        pcall(function()
            local cnt = c:call("GetInstanceCount")
            if cnt then f:write(string.format("       * ISM InstanceCount: %d\n", cnt)) end
        end)

        -- StaticMesh
        pcall(function()
            local sm = c.StaticMesh
            if sm then f:write(string.format("       * StaticMesh: %s\n", get_safe_name(sm))) end
        end)

        -- Materials & MIDs
        pcall(function()
            local num_mat = c:call("GetNumMaterials")
            if num_mat and num_mat > 0 then
                f:write(string.format("       * Materials (%d):\n", num_mat))
                for m_idx = 0, num_mat - 1 do
                    local mat = c:call("GetMaterial", m_idx)
                    f:write(string.format("         [%d] %s\n", m_idx, get_safe_name(mat)))
                end
            end
        end)
    end
    f:write("\n")

    f:write("====================================================================\n")
    f:write("  DUMP COMPLETE\n")
    f:write("====================================================================\n")
    f:close()
    S.dump_written = true
    S.last_dump_time = os.date("%H:%M:%S")
    print(string.format("[%s] Deep dump written to %s", SCRIPT_NAME, DUMP_FILE))
end

--------------------------------------------------------------------------
-- 3. World Scanner
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
    local found_containers = {}
    local aer_act = nil

    for _, a in ipairs(all_actors) do
        local fn = get_safe_name(a)
        if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
            local comps_info = {}
            if comp_class then
                local raw_comps = a:call("K2_GetComponentsByClass", comp_class) or {}
                for _, c in ipairs(raw_comps) do
                    local c_class_name = "unknown"
                    pcall(function() c_class_name = get_short_name(c:get_class()) end)
                    table.insert(comps_info, {
                        obj = c,
                        name = get_short_name(c),
                        class = c_class_name,
                        full = get_safe_name(c)
                    })
                end
            end

            table.insert(found_containers, {
                obj = a,
                name = get_short_name(a),
                full = fn,
                dist_m = calc_dist(a),
                comps = comps_info
            })
        elseif fn:find("AerialRefuel3DUIActor", 1, true) and not fn:find("Default__", 1, true) then
            aer_act = a
        end
    end

    S.containers = found_containers
    if aer_act ~= S.aerial_actor then
        S.aerial_actor = aer_act
        S.aerial_name = aer_act and get_short_name(aer_act) or "None"
    end

    -- Initialize states
    for idx = 1, #S.containers do
        if not S.container_states[idx] then
            S.container_states[idx] = { hidden = false, scale = 1.0, comp_scales = {} }
        end
    end

    -- Dump automatically on first discovery
    if #S.containers > 0 and not S.dump_written then
        dump_container_structure(S.containers[1].obj)
    end
end

--------------------------------------------------------------------------
-- 4. Multi-Layer Scaling Implementation
--------------------------------------------------------------------------
local function scale_component_exhaustive(comp, sc)
    if not comp then return end

    -- 1. Standard Scales
    pcall(function() comp:call("SetRelativeScale3D", { X = sc, Y = sc, Z = sc }) end)
    pcall(function() comp:call("SetWorldScale3D", { X = sc, Y = sc, Z = sc }) end)
    pcall(function() comp.RelativeScale3D = { X = sc, Y = sc, Z = sc } end)

    -- 2. MaterialBillboardComponent Elements BaseSize
    pcall(function()
        local elems = comp.Elements
        if elems and type(elems) == "table" then
            for _, el in ipairs(elems) do
                if el.BaseSizeX then el.BaseSizeX = 128.0 * sc end
                if el.BaseSizeY then el.BaseSizeY = 128.0 * sc end
            end
        end
    end)

    -- 3. BillboardComponent ScreenSize
    pcall(function()
        comp.ScreenSize = sc
    end)

    -- 4. Instanced Static Mesh Instance Scaling
    pcall(function()
        local cnt = comp:call("GetInstanceCount")
        if cnt and cnt > 0 then
            for i = 0, cnt - 1 do
                pcall(function()
                    local tr = {}
                    local ok = pcall(function() comp:call("GetInstanceTransform", i, tr, false) end)
                    if tr and tr.Scale3D then
                        tr.Scale3D.X = sc
                        tr.Scale3D.Y = sc
                        tr.Scale3D.Z = sc
                        comp:call("UpdateInstanceTransform", i, tr, false, true, false)
                    end
                end)
            end
        end
    end)

    -- 5. Child Actor scaling
    pcall(function()
        local ca = comp.ChildActor
        if ca then
            ca:call("SetActorScale3D", { X = sc, Y = sc, Z = sc })
            local root = ca.RootComponent
            if root then
                root:call("SetWorldScale3D", { X = sc, Y = sc, Z = sc })
            end
        end
    end)

    -- 6. Dynamic Material Parameter scaling
    pcall(function()
        local num_mat = comp:call("GetNumMaterials")
        if num_mat and num_mat > 0 then
            for m_idx = 0, num_mat - 1 do
                pcall(function()
                    local mid = comp:call("CreateAndSetMaterialInstanceDynamic", m_idx)
                    if mid then
                        for _, param in ipairs({ "Scale", "Size", "IconScale", "Radius", "MarkerSize", "UVScale" }) do
                            mid:call("SetScalarParameterValue", param, sc)
                        end
                    end
                end)
            end
        end
    end)
end

local function apply_container_transform(c_entry, hidden, scale)
    if not (c_entry and c_entry.obj) then return end
    local a = c_entry.obj

    if hidden ~= nil then
        pcall(function() a:call("SetActorHiddenInGame", hidden) end)
        for _, comp in ipairs(c_entry.comps) do
            pcall(function()
                comp.obj:call("SetVisibility", not hidden)
                comp.obj.bHiddenInGame = hidden
            end)
        end
    end

    if scale ~= nil then
        pcall(function() a:call("SetActorScale3D", { X = scale, Y = scale, Z = scale }) end)
        local root = a.RootComponent
        if root then scale_component_exhaustive(root, scale) end
        for _, comp in ipairs(c_entry.comps) do
            scale_component_exhaustive(comp.obj, scale)
        end
    end
end

local function apply_master_transform(hidden, scale)
    for idx, c_entry in ipairs(S.containers) do
        local st = S.container_states[idx]
        if st then
            if hidden ~= nil then st.hidden = hidden end
            if scale ~= nil then st.scale = scale end
        end
        apply_container_transform(c_entry, hidden, scale)
    end
end

--------------------------------------------------------------------------
-- 5. Engine Tick (Continuous Enforcement)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan every 60 ticks (1.0s)
    if tick_count % 60 == 0 then
        scan_containers()
    end

    -- Continuous enforcement on all containers
    for idx, c_entry in ipairs(S.containers) do
        local st = S.container_states[idx]
        if st then
            if st.hidden then
                apply_container_transform(c_entry, true, nil)
            end
            if math.abs(st.scale - 1.0) > 0.01 then
                apply_container_transform(c_entry, nil, st.scale)
            end

            -- Component-level specific scale overrides
            if st.comp_scales then
                for comp_idx, c_sc in pairs(st.comp_scales) do
                    local comp = c_entry.comps[comp_idx]
                    if comp and math.abs(c_sc - 1.0) > 0.01 then
                        scale_component_exhaustive(comp.obj, c_sc)
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------
-- 6. Script UI (Simple English for Japanese VR Users)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Container Deep Inspector & Scaler (v9) ===")
    imgui.text("Multi-layer scaling (Actor, Components, Billboard BaseSize, ISM, Material MID)")

    if imgui.button("Force Rescan & Deep Dump Now") then
        S.dump_written = false
        scan_containers()
        if #S.containers > 0 then dump_container_structure(S.containers[1].obj) end
    end
    imgui.same_line()
    imgui.text(string.format("Dump: %s", S.last_dump_time))

    imgui.separator()

    -- STATUS
    imgui.text(string.format("Target Container Actors Found: %d (Pattern B confirmed!)", #S.containers))

    imgui.separator()

    -- SECTION 1: MASTER CONTROLS
    imgui.text("--- 1. Master Controls (All Target Markers) ---")
    local c_mh, v_mh = imgui.checkbox("Hide ALL Target Markers in Sky##master", S.master_hidden)
    if c_mh then
        S.master_hidden = v_mh
        apply_master_transform(v_mh, nil)
    end

    local c_ms, v_ms = imgui.slider_float("Global Target Marker Scale##master", S.master_scale, 0.2, 5.0)
    if c_ms then
        S.master_scale = v_ms
        apply_master_transform(nil, v_ms)
    end

    if imgui.button("Tiny (0.5x)##m") then S.master_scale = 0.5; apply_master_transform(nil, 0.5) end
    imgui.same_line()
    if imgui.button("Normal (1.0x)##m") then S.master_scale = 1.0; apply_master_transform(nil, 1.0) end
    imgui.same_line()
    if imgui.button("Large (1.5x)##m") then S.master_scale = 1.5; apply_master_transform(nil, 1.5) end
    imgui.same_line()
    if imgui.button("Giant (3.0x)##m") then S.master_scale = 3.0; apply_master_transform(nil, 3.0) end

    imgui.separator()

    -- SECTION 2: INDIVIDUAL TARGET CONTAINERS & DETAILED COMPONENTS
    imgui.text(string.format("--- 2. Individual Target Containers (%d found) ---", #S.containers))
    for idx, c_entry in ipairs(S.containers) do
        local st = S.container_states[idx] or { hidden = false, scale = 1.0, comp_scales = {} }

        local c_ch, v_ch = imgui.checkbox(string.format("Hide [%02d]##cnt_h_%d", idx, idx), st.hidden)
        if c_ch then
            st.hidden = v_ch
            apply_container_transform(c_entry, v_ch, nil)
        end
        imgui.same_line()
        imgui.text_colored(string.format("%s (%dm)", c_entry.name, c_entry.dist_m), 0xFF44FF44)

        local c_cs, v_cs = imgui.slider_float(string.format("Actor Scale [%02d]##cnt_s_%d", idx, idx), st.scale, 0.2, 5.0)
        if c_cs then
            st.scale = v_cs
            apply_container_transform(c_entry, nil, v_cs)
        end

        -- Component Breakdown for Container [1] (or selected container)
        if idx == 1 and #c_entry.comps > 0 then
            imgui.text("   [Detailed Component Breakdown of Container 1]:")
            for comp_idx, comp in ipairs(c_entry.comps) do
                local cur_c_sc = st.comp_scales[comp_idx] or 1.0
                imgui.text(string.format("    - [%02d] %s (%s)", comp_idx, comp.name, comp.class))

                local c_sc_ch, v_sc_val = imgui.slider_float(string.format("      Comp Scale##cmp_%d", comp_idx), cur_c_sc, 0.2, 5.0)
                if c_sc_ch then
                    st.comp_scales[comp_idx] = v_sc_val
                    scale_component_exhaustive(comp.obj, v_sc_val)
                end
            end
        end
    end

    imgui.separator()

    -- SECTION 3: Aerial Refuel Controller
    imgui.text("--- 3. Aerial Refueling 3D UI Controller ---")
    if S.aerial_actor then
        imgui.text_colored(string.format(" Actor: %s", S.aerial_name), 0xFF44FF44)
        local c_ah, v_ah = imgui.checkbox("Hide Aerial Refuel UI", S.aerial_hidden)
        if c_ah then
            S.aerial_hidden = v_ah
            pcall(function() S.aerial_actor:call("SetActorHiddenInGame", v_ah) end)
        end
    else
        imgui.text_colored(" (Aerial Refuel Actor not present in current mission)", 0xFF888888)
    end

    imgui.separator()

    -- MASTER RESET
    if imgui.button("=== RESET ALL (Restore 1.0x & Show All Targets) ===") then
        S.master_hidden = false
        S.master_scale  = 1.0
        apply_master_transform(false, 1.0)
        for idx, st in ipairs(S.container_states) do
            st.hidden = false
            st.scale = 1.0
            st.comp_scales = {}
        end
        if S.aerial_actor then
            S.aerial_hidden = false
            pcall(function() S.aerial_actor:call("SetActorHiddenInGame", false) end)
        end
    end
end

-- Initial scan
scan_containers()

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
