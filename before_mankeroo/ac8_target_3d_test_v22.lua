--[[
  ============================================================================
  ac8_target_3d_test_v22.lua : Target Icon Scaler (v22 Native Architecture Edition)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Target:     ContainerBox & Target Marker Hierarchy (All Aircraft in Sky)
  Purpose:    Isolate and test genuine native Unreal Engine scaling mechanisms
              - Case 1: Billboard AddElement (32.0 ~ 512.0)
              - Case 2: RootComponent Scale (0.05 ~ 1.00, Native Default = 0.20)
              - Case 3: Screen Space Pixel Mode Toggle (bSizeIsInScreenSpace)
  Rules:
    - Exactly 1 test case = 1 slider / control + 1 reset button
    - Applies to ALL target aircraft simultaneously
    - Game thread only (on_post_engine_tick), 100% crash-safe
    - Compact UI guaranteed to display all cases without clipping
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Icon-Scaler-v22"

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
-- 1. State Table (Isolated Atomic Controls)
--------------------------------------------------------------------------
local S = {
    containers          = {},
    target_count        = 0,

    -- Case 1: Billboard AddElement Replacement Size (32.0 ~ 512.0, Default 128.0)
    c1_size             = 128.0,
    applied_c1_size     = 128.0,
    c1_element_added    = false,

    -- Case 2: RootComponent Hierarchy Scale (0.05 ~ 1.00, Native Default = 0.20)
    c2_root_scale       = 0.20,
    applied_c2_scale    = 0.20,

    -- Case 3: Billboard Screen Space Mode Toggle (Default = true)
    c3_screenspace      = true,
    applied_c3_scsp     = true,
}

--------------------------------------------------------------------------
-- 2. Target Container Scanner
--------------------------------------------------------------------------
local function scan_targets()
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    local all_actors = actor_class and actor_class:get_objects_matching(false) or {}

    local found = {}

    for _, a in ipairs(all_actors) do
        local fn = get_safe_name(a)
        if (fn:find("ChronicleTargetContainerActor", 1, true) or fn:find("LiveTargetContainerActor", 1, true))
           and not fn:find("Default__", 1, true) then

            local cb = safe_call(function() return a.ContainerBox end, nil)
            local root = safe_call(function() return a.RootComponent end, nil)

            table.insert(found, {
                actor        = a,
                name         = get_short_name(a),
                container_box= cb,
                root         = root,
                orig_mat     = cb and safe_call(function() return cb:call("GetMaterial", 0) end, nil) or nil,
            })
        end
    end

    S.containers = found
    S.target_count = #found
end

--------------------------------------------------------------------------
-- 3. Execution & Enforcement (Game Thread Only)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan every 60 ticks (1.0s)
    if tick_count % 60 == 0 then
        scan_targets()
    end

    if #S.containers == 0 then return end

    local need_c1 = math.abs(S.c1_size - S.applied_c1_size) > 1.0
    local need_c2 = math.abs(S.c2_root_scale - S.applied_c2_scale) > 0.005
    local need_c3 = (S.c3_screenspace ~= S.applied_c3_scsp)

    -- Case 1: Billboard AddElement Replacement
    if need_c1 then
        local sz = S.c1_size
        for _, entry in ipairs(S.containers) do
            local cb = entry.container_box
            if cb then
                local mat = entry.orig_mat or safe_call(function() return cb:call("GetMaterial", 0) end, nil)
                if mat then
                    -- If size is reset to 128, restore original element 0 material
                    if math.abs(sz - 128.0) < 1.0 then
                        safe_call(function()
                            cb:call("SetMaterial", 0, mat)
                            cb:call("MarkRenderStateDirty")
                        end)
                        S.c1_element_added = false
                    else
                        -- Add custom-sized billboard element
                        safe_call(function()
                            -- Signature: AddElement(Material, CurveOpacity, bScreenSpace, SizeX, SizeY, CurveSize)
                            cb:call("AddElement", mat, nil, S.c3_screenspace, sz, sz, nil)
                            -- Hide element 0 so it doesn't draw duplicate small reticle
                            cb:call("SetMaterial", 0, nil)
                            cb:call("MarkRenderStateDirty")
                        end)
                        S.c1_element_added = true
                    end
                end
            end
        end
        S.applied_c1_size = S.c1_size
    end

    -- Case 2: RootComponent Hierarchy Scale
    if need_c2 then
        local sc = S.c2_root_scale
        for _, entry in ipairs(S.containers) do
            local r = entry.root
            if r then
                safe_call(function()
                    r:call("SetRelativeScale3D", { X = sc, Y = sc, Z = sc })
                    r.RelativeScale3D = { X = sc, Y = sc, Z = sc }
                end)
            end
        end
        S.applied_c2_scale = S.c2_root_scale
    end

    -- Case 3: Billboard Screen Space Mode Toggle
    if need_c3 then
        local scsp = S.c3_screenspace
        for _, entry in ipairs(S.containers) do
            local cb = entry.container_box
            if cb then
                local mat = entry.orig_mat or safe_call(function() return cb:call("GetMaterial", 0) end, nil)
                if mat then
                    safe_call(function()
                        cb:call("AddElement", mat, nil, scsp, S.c1_size, S.c1_size, nil)
                        cb:call("MarkRenderStateDirty")
                    end)
                end
            end
        end
        S.applied_c3_scsp = S.c3_screenspace
    end
end)

--------------------------------------------------------------------------
-- 4. Compact Clean Test UI (Guaranteed Zero-Clipping)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Icon Scaler (v22 Native) ===")
    imgui.text_colored("Billboard Quad & Hierarchy Scaling | All Aircraft", 0xFF00FFCC)
    imgui.text_colored(string.format("Status: Tracking %d Target Container(s) in Sky", S.target_count), 0xFF44FF44)

    imgui.same_line()
    if imgui.button("Rescan##rescan_v22") then
        scan_targets()
    end

    imgui.separator()
    imgui.text_colored("[1 Test Case = 1 Slider + 1 Reset Button]", 0xFFFFAA00)
    imgui.spacing()

    -- Case 1: Billboard AddElement Replacement Size (32.0 ~ 512.0)
    local c1_c, c1_v = imgui.slider_float("Case 1: Reticle Size (32~512)##c1_v22", S.c1_size, 32.0, 512.0)
    if c1_c then S.c1_size = c1_v end
    imgui.same_line()
    if imgui.button("128 Reset##rst_c1_v22") then S.c1_size = 128.0 end

    -- Case 2: RootComponent Hierarchy Scale (0.05 ~ 1.00)
    local c2_c, c2_v = imgui.slider_float("Case 2: Root Hierarchy Scale (0.05~1.0)##c2_v22", S.c2_root_scale, 0.05, 1.0)
    if c2_c then S.c2_root_scale = c2_v end
    imgui.same_line()
    if imgui.button("0.20 Reset##rst_c2_v22") then S.c2_root_scale = 0.20 end

    -- Case 3: Screen Space Pixel Mode Toggle
    local c3_c, c3_v = imgui.checkbox("Case 3: Fixed Screen Pixels (vs World Distance)##c3_v22", S.c3_screenspace)
    if c3_c then S.c3_screenspace = c3_v end
    imgui.same_line()
    if imgui.button("Default Reset##rst_c3_v22") then S.c3_screenspace = true end

    imgui.separator()
    imgui.spacing()

    -- Master Reset
    if imgui.button("=== Reset All to Default##rst_all_v22 ===") then
        S.c1_size        = 128.0
        S.c2_root_scale  = 0.20
        S.c3_screenspace = true
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
