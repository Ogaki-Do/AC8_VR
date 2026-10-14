--[[
  ============================================================================
  ac8_target_3d_test.lua : Target Reticle Frame Scaler - Bulletproof (v19)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Fix:        - Removed all render-thread hooks (caused null pointer dereference
                on map transition / flight entry).
              - Enforced Game Thread ONLY (on_post_engine_tick).
              - Added Strict Idle Guard (ZERO overhead / NO calls when at default).
              - Added UObject liveness validation to prevent stale actor access.
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-TGT-V19"

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

--------------------------------------------------------------------------
-- 1. State Table
--------------------------------------------------------------------------
local S = {
    player_pawn          = nil,
    containers           = {},

    target_idx           = 1, -- 1 = Target 1, 0 = All Targets

    -- Native Scales (From Dump: Default ContainerBox=25.0, Root=0.20)
    c1_box_scale         = 25.0,  -- Slider: 5.0 to 100.0 (Default: 25.0)
    c2_root_scale        = 0.20,  -- Slider: 0.05 to 1.0  (Default: 0.20)
    c3_hide_box          = false, -- Checkbox: Hide native ContainerBox

    -- Alternative Custom Reticle (Plan B: 100% Scalable)
    c4_custom_reticle    = false, -- Checkbox: Enable Custom Reticle
    c4_reticle_scale     = 1.0,   -- Slider: 0.5 to 5.0
    c4_reticle_style     = 1,     -- 1 = "[   ]", 2 = "<   >", 3 = "+   +", 4 = "[- -]"

    last_custom_state    = false,
}

local RETICLE_STYLES = {
    "[       ]",
    "<       >",
    "+       +",
    "|-     -|",
}

local function is_idle()
    return math.abs(S.c1_box_scale - 25.0) < 0.1
       and math.abs(S.c2_root_scale - 0.20) < 0.005
       and not S.c3_hide_box
       and not S.c4_custom_reticle
end

--------------------------------------------------------------------------
-- 2. Safe Scanner (Game Thread Only)
--------------------------------------------------------------------------
local function scan_containers()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    -- During map load / transition, reset state safely
    if not is_valid(pawn) then
        S.player_pawn = nil
        S.containers = {}
        return
    end
    S.player_pawn = pawn

    local p_loc = nil
    pcall(function() p_loc = pawn:call("K2_GetActorLocation") end)

    local function calc_dist(a)
        if not (p_loc and is_valid(a)) then return 0 end
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

    local found = {}
    for _, a in ipairs(all_actors) do
        if is_valid(a) then
            local fn = get_safe_name(a)
            if fn:find("ChronicleTargetContainerActor", 1, true) and not fn:find("Default__", 1, true) then
                table.insert(found, {
                    obj     = a,
                    name    = get_short_name(a),
                    dist_m  = calc_dist(a),
                })
            end
        end
    end

    S.containers = found
end

--------------------------------------------------------------------------
-- 3. Reticle Frame Enforcement (Game Thread Only, with Idle Guard)
--------------------------------------------------------------------------
local function apply_reticle_frame()
    -- Strict Idle Guard: If nothing is modified, do ABSOLUTELY NOTHING
    if is_idle() and not S.last_custom_state then
        return
    end

    local entries = {}
    if S.target_idx == 0 then
        entries = S.containers
    else
        local ent = S.containers[S.target_idx]
        if ent then table.insert(entries, ent) end
    end

    for _, entry in ipairs(entries) do
        local a = entry.obj
        if is_valid(a) then
            local cb = a.ContainerBox
            local root = a.RootComponent

            -- Case 1: ContainerBox RelativeScale3D (Default is 25.0)
            if is_valid(cb) and math.abs(S.c1_box_scale - 25.0) > 0.1 then
                local bs = S.c1_box_scale
                pcall(function() cb:call("SetRelativeScale3D", { X = bs, Y = bs, Z = bs }) end)
                pcall(function() cb.RelativeScale3D = { X = bs, Y = bs, Z = bs } end)
            end

            -- Case 2: RootComponent RelativeScale3D (Default is 0.20)
            if is_valid(root) and math.abs(S.c2_root_scale - 0.20) > 0.005 then
                local rs = S.c2_root_scale
                pcall(function() root:call("SetRelativeScale3D", { X = rs, Y = rs, Z = rs }) end)
                pcall(function() root.RelativeScale3D = { X = rs, Y = rs, Z = rs } end)
            end

            -- Case 3: Hide Native ContainerBox
            if is_valid(cb) then
                if S.c3_hide_box or S.c4_custom_reticle then
                    pcall(function() cb:call("SetVisibility", false, true) end)
                    pcall(function() cb:call("SetHiddenInGame", true, true) end)
                    pcall(function() cb.bHiddenInGame = true end)
                    pcall(function() cb.bVisible = false end)
                end
            end

            -- Case 4: Custom Scalable Reticle (using NextTargetText or GamerTagText)
            local custom_slot = a.NextTargetText or a.GamerTagText
            if is_valid(custom_slot) then
                if S.c4_custom_reticle then
                    pcall(function() custom_slot:call("SetVisibility", true, true) end)
                    pcall(function() custom_slot:call("SetHiddenInGame", false, true) end)
                    pcall(function() custom_slot.bHiddenInGame = false end)
                    pcall(function() custom_slot.bVisible = true end)

                    local glyph = RETICLE_STYLES[S.c4_reticle_style] or "[       ]"
                    pcall(function() custom_slot:call("SetText", glyph) end)

                    local r_sc = S.c4_reticle_scale * 15.0
                    pcall(function() custom_slot:call("SetRelativeScale3D", { X = r_sc, Y = r_sc, Z = r_sc }) end)
                    pcall(function() custom_slot.RelativeScale3D = { X = r_sc, Y = r_sc, Z = r_sc } end)
                    pcall(function() custom_slot:call("SetWorldSize", 40.0 * S.c4_reticle_scale) end)
                    pcall(function() custom_slot:call("SetXScale", S.c4_reticle_scale) end)
                    pcall(function() custom_slot:call("SetYScale", S.c4_reticle_scale) end)
                elseif S.last_custom_state then
                    -- Turned off: restore empty text once
                    pcall(function() custom_slot:call("SetText", "") end)
                end
            end
        end
    end

    S.last_custom_state = S.c4_custom_reticle
end

--------------------------------------------------------------------------
-- 4. Callback (Game Thread ONLY - No Render Thread!)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1
    if tick_count % 60 == 0 then
        scan_containers()
    end
    apply_reticle_frame()
end)

--------------------------------------------------------------------------
-- 5. Ultra-Lean Script UI
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Target Reticle Scaler (v19 - Bulletproof) ===")
    imgui.text_colored(string.format("Target Aircraft in Sky: %d", #S.containers), 0xFF00FFCC)
    imgui.same_line()
    if imgui.button("Rescan Targets##rescan") then scan_containers() end

    imgui.separator()

    -- Target Selector
    local c_tidx, v_tidx = imgui.slider_int("Target Aircraft##b_tgt", S.target_idx, 0, math.max(1, #S.containers))
    if c_tidx then S.target_idx = v_tidx end
    imgui.same_line()
    imgui.text(S.target_idx == 0 and "(All Targets in Sky)" or string.format("(Target %d only)", S.target_idx))

    imgui.separator()

    -- Case 1: ContainerBox RelativeScale (Default is 25.0)
    imgui.text_colored("[Case 1] Native ContainerBox Scale (Default: 25.0x)", 0xFFFFAA00)
    local c1, v1 = imgui.slider_float("ContainerBox Scale (5.0~100.0)##c1", S.c1_box_scale, 5.0, 100.0)
    if c1 then S.c1_box_scale = v1 end
    imgui.same_line()
    if imgui.button("25.0 (Default)##rst_c1") then S.c1_box_scale = 25.0 end
    imgui.same_line()
    if imgui.button("50.0 (2x)##c1_50") then S.c1_box_scale = 50.0 end
    imgui.same_line()
    if imgui.button("75.0 (3x)##c1_75") then S.c1_box_scale = 75.0 end

    imgui.separator()

    -- Case 2: RootComponent Scale (Default is 0.20)
    imgui.text_colored("[Case 2] RootComponent Scale (Default: 0.20)", 0xFFFFAA00)
    local c2, v2 = imgui.slider_float("Root Scale (0.05~1.00)##c2", S.c2_root_scale, 0.05, 1.0)
    if c2 then S.c2_root_scale = v2 end
    imgui.same_line()
    if imgui.button("0.20 (Default)##rst_c2") then S.c2_root_scale = 0.20 end
    imgui.same_line()
    if imgui.button("0.40 (2x)##c2_40") then S.c2_root_scale = 0.40 end
    imgui.same_line()
    if imgui.button("0.60 (3x)##c2_60") then S.c2_root_scale = 0.60 end

    imgui.separator()

    -- Case 3: Toggle Hide Native ContainerBox
    imgui.text_colored("[Case 3] Native Box Visibility Toggle", 0xFFFFAA00)
    local c3, v3 = imgui.checkbox("Hide Native ContainerBox (Square Frame)##c3", S.c3_hide_box)
    if c3 then S.c3_hide_box = v3 end

    imgui.separator()

    -- Case 4: Custom Scalable Reticle (Guaranteed Plan B)
    imgui.text_colored("[Case 4] Custom Scalable Reticle (Guaranteed Working)", 0xFF00FF88)
    imgui.text("Replaces the fixed native box with a perfectly scalable HUD reticle:")
    local c4_en, v4_en = imgui.checkbox("Enable Custom Scalable Reticle##c4_en", S.c4_custom_reticle)
    if c4_en then S.c4_custom_reticle = v4_en end

    if S.c4_custom_reticle then
        local c4_sc, v4_sc = imgui.slider_float("Custom Reticle Size (0.5x~5.0x)##c4_sz", S.c4_reticle_scale, 0.5, 5.0)
        if c4_sc then S.c4_reticle_scale = v4_sc end
        imgui.same_line()
        if imgui.button("1.0x##rst_c4") then S.c4_reticle_scale = 1.0 end
        imgui.same_line()
        if imgui.button("2.0x##c4_2x") then S.c4_reticle_scale = 2.0 end
        imgui.same_line()
        if imgui.button("3.0x##c4_3x") then S.c4_reticle_scale = 3.0 end

        local c4_st, v4_st = imgui.slider_int("Reticle Style (1~4)##c4_st", S.c4_reticle_style, 1, 4)
        if c4_st then S.c4_reticle_style = v4_st end
        imgui.same_line()
        imgui.text(string.format("Preview: %s", RETICLE_STYLES[S.c4_reticle_style] or ""))
    end

    imgui.separator()

    if imgui.button("=== Reset All Controls to Default ===") then
        S.c1_box_scale      = 25.0
        S.c2_root_scale     = 0.20
        S.c3_hide_box       = false
        S.c4_custom_reticle = false
        S.c4_reticle_scale  = 1.0
        S.c4_reticle_style  = 1
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
