--[[
  ============================================================================
  ac8_target_3d_test_v21.lua : Target Icon Scaler (v21 Native Memory Edition)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Target:     ContainerBox (UMaterialBillboardComponent.Elements[0])
  Purpose:    Direct native memory manipulation of billboard BaseSizeX & BaseSizeY
              - Case 1: Native Target Icon Size (32.0 ~ 1024.0)
              - Case 2: Screen Space Mode Toggle (Screen Pixels vs World Size)
              - Case 3: RelativeScale3D Override (1.0 ~ 50.0)
  Rules:
    - 1 test case = 1 slider / control + 1 reset button (strictly isolated)
    - Applies to ALL target aircraft in the sky simultaneously
    - Game thread only (on_post_engine_tick), 100% crash-safe
    - No scratch/custom UI, no JHMCS clutter (JHMCS is handled in ac8_m_jhmcs.lua)
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Icon-Scaler-v21"

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
-- 1. Memory Access Functions Resolution
--------------------------------------------------------------------------
local _read_qword   = read_qword   or (uevr and uevr.read_qword)   or (api and api.read_qword)
local _read_dword   = read_dword   or (uevr and uevr.read_dword)   or (api and api.read_dword)
local _read_float   = read_float   or (uevr and uevr.read_float)   or (api and api.read_float)
local _write_float  = write_float  or (uevr and uevr.write_float)  or (api and api.write_float)
local _write_dword  = write_dword  or (uevr and uevr.write_dword)  or (api and api.write_dword)

local has_memory_api = (_read_qword ~= nil and _read_float ~= nil and _write_float ~= nil)

-- Resolve offset of 'Elements' in UMaterialBillboardComponent via reflection
local elements_offset = nil
do
    local mbc_class = api:find_uobject("Class /Script/Engine.MaterialBillboardComponent")
    if mbc_class then
        local p = safe_call(function() return mbc_class:find_property("Elements") end, nil)
        if p then
            elements_offset = safe_call(function() return p:get_offset() end, nil)
        end
    end
end

--------------------------------------------------------------------------
-- 2. State Table (Isolated Atomic Controls)
--------------------------------------------------------------------------
local S = {
    containers          = {},
    player_pawn         = nil,
    target_count        = 0,

    -- Diagnostics read from memory
    detected_base_x     = -1.0,
    detected_base_y     = -1.0,
    detected_num_elem   = -1,
    detected_screen_sp  = false,
    struct_aligned      = false,

    -- Case 1: Native Target Icon Size (32.0 ~ 1024.0)
    c1_icon_size        = 128.0,
    applied_icon_size   = 128.0,

    -- Case 2: Screen Space Mode Toggle
    c2_screen_space     = true,
    applied_screen_sp   = true,

    -- Case 3: RelativeScale3D Override (1.0 ~ 50.0)
    c3_scale            = 25.0,
    applied_scale       = 25.0,
}

--------------------------------------------------------------------------
-- 3. Target Actor Scanner (All Aircraft in Sky)
--------------------------------------------------------------------------
local function scan_targets()
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
        local a_loc = safe_call(function() return a:call("K2_GetActorLocation") end, nil)
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
                local raw_comps = safe_call(function() return a:call("K2_GetComponentsByClass", comp_class) end, {}) or {}
                for _, c in ipairs(raw_comps) do
                    table.insert(comps, {
                        obj   = c,
                        name  = get_short_name(c),
                        class = get_short_name(safe_call(function() return c:get_class() end, nil))
                    })
                end
            end

            table.insert(found, {
                obj    = a,
                name   = get_short_name(a),
                dist_m = calc_dist(a),
                comps  = comps
            })
        end
    end

    S.containers = found
    S.target_count = #found
end

--------------------------------------------------------------------------
-- 4. Native Memory Application & Enforcement (Game Thread Only)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan every 60 ticks (1.0s)
    if tick_count % 60 == 0 then
        scan_targets()
    end

    if #S.containers == 0 or not elements_offset or not has_memory_api then return end

    local need_apply_size = math.abs(S.c1_icon_size - S.applied_icon_size) > 0.5
    local need_apply_scsp = (S.c2_screen_space ~= S.applied_screen_sp)
    local need_apply_sc   = math.abs(S.c3_scale - S.applied_scale) > 0.1

    for idx, entry in ipairs(S.containers) do
        for _, comp_info in ipairs(entry.comps) do
            local c = comp_info.obj
            if c and comp_info.name == "ContainerBox" then
                local cb_addr = safe_call(function() return c:get_address() end, 0)
                if cb_addr ~= 0 then
                    -- Pointer to TArray<FMaterialSpriteElement>.Data
                    local data_ptr = safe_call(function() return _read_qword(cb_addr + elements_offset) end, 0)
                    local num_elem = safe_call(function() return _read_dword(cb_addr + elements_offset + 8) end, 0)

                    if data_ptr ~= 0 and num_elem > 0 then
                        -- Inspect first container on tick 30
                        if idx == 1 and tick_count % 30 == 0 then
                            pcall(function()
                                S.detected_num_elem = num_elem
                                S.detected_base_x   = _read_float(data_ptr + 0x14)
                                S.detected_base_y   = _read_float(data_ptr + 0x18)
                                local sc_bits       = _read_dword(data_ptr + 0x10)
                                S.detected_screen_sp = (sc_bits ~= 0)

                                local mat_addr = safe_call(function()
                                    local m = c:call("GetMaterial", 0)
                                    return m and m:get_address() or 0
                                end, 0)
                                local elem_mat = _read_qword(data_ptr)
                                S.struct_aligned = (mat_addr ~= 0 and mat_addr == elem_mat)
                            end)
                        end

                        -- Case 1: Apply Native Icon Size (BaseSizeX & BaseSizeY)
                        if need_apply_size then
                            local sz = S.c1_icon_size
                            safe_call(function()
                                _write_float(data_ptr + 0x14, sz)
                                _write_float(data_ptr + 0x18, sz)
                                c:call("MarkRenderStateDirty")
                            end)
                        end

                        -- Case 2: Apply Screen Space Mode Toggle
                        if need_apply_scsp then
                            local val = S.c2_screen_space and 1 or 0
                            safe_call(function()
                                _write_dword(data_ptr + 0x10, val)
                                c:call("MarkRenderStateDirty")
                            end)
                        end
                    end

                    -- Case 3: Apply RelativeScale3D
                    if need_apply_sc then
                        local sc = S.c3_scale
                        safe_call(function()
                            c:call("SetRelativeScale3D", { X = sc, Y = sc, Z = sc })
                            c.RelativeScale3D = { X = sc, Y = sc, Z = sc }
                        end)
                    end
                end
            end
        end
    end

    if need_apply_size then S.applied_icon_size = S.c1_icon_size end
    if need_apply_scsp then S.applied_screen_sp = S.c2_screen_space end
    if need_apply_sc   then S.applied_scale     = S.c3_scale end
end)

--------------------------------------------------------------------------
-- 5. Ultra-Lean Test UI (1 Slider / Control per Case)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Icon Scaler (v21 Native Memory) ===")
    imgui.text_colored("Direct Engine Billboard Quad Scaling | Applied to ALL Aircraft", 0xFF00FFCC)

    imgui.text_colored(string.format("Status: Tracking %d Target(s) in Sky", S.target_count), 0xFF44FF44)
    imgui.same_line()
    if imgui.button("Rescan Targets##rescan") then
        scan_targets()
    end

    -- Diagnostic Readout
    if has_memory_api and elements_offset then
        local align_str = S.struct_aligned and "[Struct Aligned: YES]" or "[Struct Aligned: PENDING]"
        local align_col = S.struct_aligned and 0xFF44FF44 or 0xFFFFFF00
        imgui.text_colored(string.format("Memory: Elements Offset=0x%X | %s", elements_offset, align_str), align_col)
        imgui.text(string.format("Current Memory BaseSize: (X=%.1f, Y=%.1f) | ScreenSpace=%s",
            S.detected_base_x, S.detected_base_y, tostring(S.detected_screen_sp)))
    else
        imgui.text_colored("Warning: Memory API or Elements Offset unavailable!", 0xFFFF4444)
    end

    imgui.separator()
    imgui.text_colored("[1 Test Case = 1 Slider + 1 Reset Button]", 0xFFFFAA00)
    imgui.spacing()

    -- Case 1: Native Target Icon Size (BaseSizeX & BaseSizeY in Memory)
    local c1_c, c1_v = imgui.slider_float("Case 1: Native Icon Size (32~1024)##c1", S.c1_icon_size, 32.0, 1024.0)
    if c1_c then S.c1_icon_size = c1_v end
    imgui.same_line()
    if imgui.button("128 Reset##rst_c1") then S.c1_icon_size = 128.0 end
    imgui.text_disabled(" *Directly writes BaseSizeX & BaseSizeY into Billboard Element 0")

    -- Case 2: Screen Space Mode Toggle
    local c2_c, c2_v = imgui.checkbox("Case 2: Screen Space Mode (Fixed Pixels vs World Units)##c2", S.c2_screen_space)
    if c2_c then S.c2_screen_space = c2_v end
    imgui.same_line()
    if imgui.button("Default Reset##rst_c2") then S.c2_screen_space = true end

    -- Case 3: RelativeScale3D Override
    local c3_c, c3_v = imgui.slider_float("Case 3: RelativeScale3D (1.0~50.0)##c3", S.c3_scale, 1.0, 50.0)
    if c3_c then S.c3_scale = c3_v end
    imgui.same_line()
    if imgui.button("25.0 Reset##rst_c3") then S.c3_scale = 25.0 end

    imgui.separator()
    imgui.spacing()

    -- Master Reset
    if imgui.button("=== Reset All to Default ===") then
        S.c1_icon_size    = 128.0
        S.c2_screen_space = true
        S.c3_scale        = 25.0
    end
end

-- Initial scan
scan_targets()

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
