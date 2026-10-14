--[[
  ============================================================================
  ac8_m_jhmcs.lua : VR Joint Helmet Mounted Cueing System (360° Target Lock)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Feature:    JHMCS 360° All-Aspect Target Marker System (Production Release)
              - Unlocks target markers beyond the default 100° cockpit HUD FOV
              - Overrides game engine FOV culling, keeping target reticles and
                data visible 360° around the cockpit for high-off-boresight tracking
              - Displays live target count and distance for all aircraft in sky
  Position:   Loaded immediately after AC8 HUD tune (ac8_ladder_fix_v19_fast.lua)
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-JHMCS"

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
    enabled         = true,
    containers      = {}, -- list of { obj, name, dist_m, comps = {} }
    player_pawn     = nil,
    target_count    = 0,
}

--------------------------------------------------------------------------
-- 2. Scanner for Target Containers in Sky
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
                    table.insert(comps, c)
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
-- 3. Continuous Enforcement (360° All-Aspect Visibility)
--------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    -- Periodic rescan every 60 ticks (1.0s)
    if tick_count % 60 == 0 then
        scan_targets()
    end

    -- Keep target markers visible 360° around player
    if S.enabled then
        for _, entry in ipairs(S.containers) do
            local a = entry.obj
            if a then
                pcall(function()
                    a:call("SetActorHiddenInGame", false)
                    a.bHiddenInGame = false
                end)
                local root = a.RootComponent
                if root then
                    pcall(function()
                        root:call("SetVisibility", true)
                        root.bHiddenInGame = false
                    end)
                end
                for _, c in ipairs(entry.comps) do
                    pcall(function()
                        c:call("SetVisibility", true)
                        c.bHiddenInGame = false
                    end)
                end
            end
        end
    end
end)

--------------------------------------------------------------------------
-- 4. Script UI (Simple English for Japanese VR Users)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 JHMCS : 360° Target Marker Cueing ===")
    imgui.text_colored("High-Off-Boresight Target Tracking for VR", 0xFF00FFCC)

    local changed, val = imgui.checkbox("Enable 360° JHMCS Target Lock##jhmcs_en", S.enabled)
    if changed then S.enabled = val end

    imgui.same_line()
    if imgui.button("Rescan Targets##jhmcs_rescan") then
        scan_targets()
    end

    imgui.separator()

    if S.enabled then
        imgui.text_colored(string.format("JHMCS Active: Tracking %d Target(s) in Sky", S.target_count), 0xFF44FF44)
    else
        imgui.text_colored("JHMCS Disabled: Game default FOV culling restored", 0xFF888888)
    end

    imgui.separator()

    imgui.text(string.format("Tracked Aircraft (%d):", S.target_count))
    for idx, entry in ipairs(S.containers) do
        imgui.text(string.format(" [%02d] %s (%dm)", idx, entry.name, entry.dist_m))
    end
end

-- Initial scan
scan_targets()

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully. Positioned after HUD tune.", SCRIPT_NAME))
