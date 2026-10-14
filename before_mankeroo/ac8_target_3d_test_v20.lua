--[[
  ============================================================================
  ac8_target_3d_test_v20.lua : Target Icon Scaler & Shader Test (v20 Ultra-Lean)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Target:     ContainerBox (UMaterialBillboardComponent) on ChronicleTargetContainerActorBP_C
  Purpose:    Isolate and test direct native scaling of the target square reticle
              - Case 1: Shader Reticle Scale (1.0 ~ 5.0)
              - Case 2: Shader Reticle Size (32 ~ 512)
              - Case 3: Shader UV / Texture Scale (0.2 ~ 5.0)
              - Case 4: Shader Diagnostic Color Shift (Magenta Tint Test)
              - Case 5: Billboard AddElement BaseSize (64 ~ 1024)
  Rules:
    - 1 test case = 1 slider + 1 reset button (strictly isolated)
    - Applies to ALL target aircraft in the sky simultaneously
    - Game thread only (on_post_engine_tick), 100% crash-safe
    - No scratch/custom UI, no JHMCS clutter (JHMCS is handled in ac8_m_jhmcs.lua)
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Icon-Scaler-v20"

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
-- 1. State Table (5 Atomic Sliders)
--------------------------------------------------------------------------
local S = {
    containers     = {}, -- list of target actors & components
    player_pawn    = nil,
    target_count   = 0,

    -- 5 Atomic Test Cases (All applied to ALL targets)
    c1_scale       = 1.0,    -- Case 1: Shader Reticle Scale (1.0 ~ 5.0)
    c2_size        = 128.0,  -- Case 2: Shader Reticle Size (32.0 ~ 512.0)
    c3_uv_scale    = 1.0,    -- Case 3: Shader UV Scale (0.2 ~ 5.0)
    c4_color_shift = 0.0,    -- Case 4: Diagnostic Color Shift (0.0 = Normal, 1.0 = Magenta)
    c5_base_size   = 128.0,  -- Case 5: AddElement BaseSize (64.0 ~ 1024.0)

    -- Tracking state for one-shot element injection
    last_injected_size = 0.0,
}

--------------------------------------------------------------------------
-- 2. Target Actor Scanner (All Aircraft in Sky)
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
-- 3. One-Shot Material Parameter Discovery in Background
--------------------------------------------------------------------------
local param_discovery_done = false
local function discover_material_parameters()
    if param_discovery_done then return end
    param_discovery_done = true

    local lines = {}
    local function log_l(fmt, ...) table.insert(lines, string.format(fmt, ...)) end

    log_l("====================================================================")
    log_l("  AC8 TARGET RETICLE MATERIAL PARAMETER DISCOVERY REPORT")
    log_l("  Time: %s", os.date("%Y-%m-%d %H:%M:%S"))
    log_l("====================================================================")

    local scalar_class = api:find_uobject("Class /Script/Engine.MaterialExpressionScalarParameter")
    if scalar_class then
        local objs = scalar_class:get_objects_matching(false) or {}
        log_l("MaterialExpressionScalarParameter total: %d", #objs)
        for _, o in ipairs(objs) do
            local fn = get_safe_name(o)
            if fn:find("TargetContainer", 1, true) or fn:find("TargetPin", 1, true) or fn:find("HUD", 1, true) then
                local pname = "nil"
                local pdef = "nil"
                pcall(function() pname = o.ParameterName:to_string() end)
                pcall(function() pdef = tostring(o.DefaultValue) end)
                log_l("  [SCALAR] %s", fn)
                log_l("           ParameterName = '%s' | DefaultValue = %s", pname, pdef)
            end
        end
    end

    local vec_class = api:find_uobject("Class /Script/Engine.MaterialExpressionVectorParameter")
    if vec_class then
        local objs = vec_class:get_objects_matching(false) or {}
        log_l("MaterialExpressionVectorParameter total: %d", #objs)
        for _, o in ipairs(objs) do
            local fn = get_safe_name(o)
            if fn:find("TargetContainer", 1, true) or fn:find("TargetPin", 1, true) or fn:find("HUD", 1, true) then
                local pname = "nil"
                pcall(function() pname = o.ParameterName:to_string() end)
                log_l("  [VECTOR] %s | ParameterName = '%s'", fn, pname)
            end
        end
    end

    local f = io.open([[d:\Ogaki\Desktop\Ace-uevr-test\data\ac8_material_parameters_found.txt]], "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
        print(string.format("[%s] Material parameter report saved.", SCRIPT_NAME))
    end
end

--------------------------------------------------------------------------
-- 4. Continuous Execution: Apply Test Controls (Game Thread Only)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan every 60 ticks (1.0s)
    if tick_count % 60 == 0 then
        scan_targets()
    end

    -- Run background parameter discovery on tick 5
    if tick_count == 5 then
        pcall(discover_material_parameters)
    end

    if #S.containers == 0 then return end

    -- Apply active test cases to ALL target aircraft in the sky
    for _, entry in ipairs(S.containers) do
        for _, comp_info in ipairs(entry.comps) do
            local c = comp_info.obj
            if c and comp_info.name == "ContainerBox" then
                -- Get the active MaterialInstanceDynamic directly from element 0
                local mid = safe_call(function() return c:call("GetMaterial", 0) end, nil)
                            or safe_call(function() return c.Material end, nil)

                -- Case 1: Shader Reticle Scale (Scale / IconScale / ReticleScale)
                if math.abs(S.c1_scale - 1.0) > 0.01 and mid then
                    local sc = S.c1_scale
                    pcall(function()
                        mid:call("SetScalarParameterValue", "Scale", sc)
                        mid:call("SetScalarParameterValue", "IconScale", sc)
                        mid:call("SetScalarParameterValue", "ReticleScale", sc)
                        mid:call("SetScalarParameterValue", "BoxScale", sc)
                        mid:call("SetScalarParameterValue", "UI_Scale", sc)
                        mid:call("SetScalarParameterValue", "DrawScale", sc)
                        mid:call("SetScalarParameterValue", "MarkerScale", sc)
                    end)
                end

                -- Case 2: Shader Reticle Size (Size / IconSize / ReticleSize / BoxSize)
                if math.abs(S.c2_size - 128.0) > 1.0 and mid then
                    local sz = S.c2_size
                    pcall(function()
                        mid:call("SetScalarParameterValue", "Size", sz)
                        mid:call("SetScalarParameterValue", "IconSize", sz)
                        mid:call("SetScalarParameterValue", "ReticleSize", sz)
                        mid:call("SetScalarParameterValue", "BoxSize", sz)
                        mid:call("SetScalarParameterValue", "TargetSize", sz)
                        mid:call("SetScalarParameterValue", "Radius", sz)
                        mid:call("SetScalarParameterValue", "Dimension", sz)
                    end)
                end

                -- Case 3: Shader UV Scale (UVScale / Tiling / Zoom)
                if math.abs(S.c3_uv_scale - 1.0) > 0.01 and mid then
                    local uv = S.c3_uv_scale
                    pcall(function()
                        mid:call("SetScalarParameterValue", "UVScale", uv)
                        mid:call("SetScalarParameterValue", "Tiling", uv)
                        mid:call("SetScalarParameterValue", "Zoom", uv)
                        mid:call("SetScalarParameterValue", "TextureScale", uv)
                        mid:call("SetScalarParameterValue", "TexScale", uv)
                    end)
                end

                -- Case 4: Diagnostic Color Shift (Magenta Tint Test)
                if S.c4_color_shift > 0.01 and mid then
                    local r = S.c4_color_shift
                    pcall(function()
                        -- Blend from green (0,1,0) towards magenta (1,0,1)
                        local col = { R = r, G = 1.0 - r, B = r, A = 1.0 }
                        mid:call("SetVectorParameterValue", "Color", col)
                        mid:call("SetVectorParameterValue", "TargetColor", col)
                        mid:call("SetVectorParameterValue", "BoxColor", col)
                        mid:call("SetVectorParameterValue", "ReticleColor", col)
                    end)
                end

                -- Case 5: AddElement BaseSize (Direct Element Quad Injection)
                if math.abs(S.c5_base_size - S.last_injected_size) > 1.0 then
                    local bsz = S.c5_base_size
                    if mid then
                        pcall(function()
                            c:call("AddElement", mid, nil, true, bsz, bsz, nil)
                            c:call("MarkRenderStateDirty")
                        end)
                    end
                end
            end
        end
    end

    if math.abs(S.c5_base_size - S.last_injected_size) > 1.0 then
        S.last_injected_size = S.c5_base_size
    end
end)

--------------------------------------------------------------------------
-- 5. Ultra-Lean Test UI (1 Slider / Control per Case)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Icon Scaler (v20) ===")
    imgui.text_colored("Target: ContainerBox (Square Reticle) | Applied to ALL Aircraft", 0xFF00FFCC)

    imgui.text_colored(string.format("Status: Tracking %d Target(s) in Sky", S.target_count), 0xFF44FF44)
    imgui.same_line()
    if imgui.button("Rescan Targets##rescan") then
        scan_targets()
    end

    imgui.separator()
    imgui.text_colored("[1 Test Case = 1 Slider + 1 Reset Button]", 0xFFFFAA00)
    imgui.spacing()

    -- Case 1: Shader Reticle Scale (1.0 ~ 5.0)
    local c1_c, c1_v = imgui.slider_float("Case 1: Shader Reticle Scale (1.0~5.0)##c1", S.c1_scale, 1.0, 5.0)
    if c1_c then S.c1_scale = c1_v end
    imgui.same_line()
    if imgui.button("1.0 Reset##rst_c1") then S.c1_scale = 1.0 end

    -- Case 2: Shader Reticle Size (32 ~ 512)
    local c2_c, c2_v = imgui.slider_float("Case 2: Shader Reticle Size (32~512)##c2", S.c2_size, 32.0, 512.0)
    if c2_c then S.c2_size = c2_v end
    imgui.same_line()
    if imgui.button("128 Reset##rst_c2") then S.c2_size = 128.0 end

    -- Case 3: Shader UV / Texture Scale (0.2 ~ 5.0)
    local c3_c, c3_v = imgui.slider_float("Case 3: Shader UV Scale (0.2~5.0)##c3", S.c3_uv_scale, 0.2, 5.0)
    if c3_c then S.c3_uv_scale = c3_v end
    imgui.same_line()
    if imgui.button("1.0 Reset##rst_c3") then S.c3_uv_scale = 1.0 end

    -- Case 4: Diagnostic Color Shift (0.0 ~ 1.0)
    local c4_c, c4_v = imgui.slider_float("Case 4: Diagnostic Color Shift (Magenta Tint)##c4", S.c4_color_shift, 0.0, 1.0)
    if c4_c then S.c4_color_shift = c4_v end
    imgui.same_line()
    if imgui.button("0.0 Reset##rst_c4") then S.c4_color_shift = 0.0 end
    imgui.text_disabled(" *Test to confirm if shader parameters can visually alter the box")

    -- Case 5: Billboard AddElement BaseSize (64 ~ 1024)
    local c5_c, c5_v = imgui.slider_float("Case 5: Billboard AddElement BaseSize (64~1024)##c5", S.c5_base_size, 64.0, 1024.0)
    if c5_c then S.c5_base_size = c5_v end
    imgui.same_line()
    if imgui.button("128 Reset##rst_c5") then S.c5_base_size = 128.0 end

    imgui.separator()
    imgui.spacing()

    -- Master Reset
    if imgui.button("=== Reset All 5 Sliders to Default ===") then
        S.c1_scale       = 1.0
        S.c2_size        = 128.0
        S.c3_uv_scale    = 1.0
        S.c4_color_shift = 0.0
        S.c5_base_size   = 128.0
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
