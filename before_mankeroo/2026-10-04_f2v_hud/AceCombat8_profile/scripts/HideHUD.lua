--[[
  ============================================================================
  HideHUD.lua : Cockpit Mesh & Interior Toggle (Open Cockpit Mode)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Feature:    Hides the aircraft cockpit interior & HUD glass mesh to provide
              a 100% unobstructed panoramic 360-degree VR flight view
              (formerly TEST 8 in target debug investigations).

  Usage:      Press Insert -> ScriptUI -> Toggle "Hide Cockpit Mesh"
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "HideHUD"
local hide_cockpit = false

local function get_safe_name(obj)
    if not obj then return "" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or ""
end

local function set_cockpit_visibility(should_hide)
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    if not pawn then return end

    local mesh_class = api:find_uobject("Class /Script/Engine.MeshComponent")
    if not mesh_class then return end

    local meshes = pawn:call("K2_GetComponentsByClass", mesh_class) or {}
    for _, m in ipairs(meshes) do
        local fn = get_safe_name(m):lower()
        if fn:find("cockpit", 1, true) or fn:find("glass", 1, true) or fn:find("hud", 1, true) then
            -- should_hide == true -> SetVisibility(false)
            pcall(function() m:call("SetVisibility", not should_hide) end)
        end
    end
end

-- Tick loop to maintain state across level / seat changes
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1
    if hide_cockpit and (tick_count % 30 == 0) then
        set_cockpit_visibility(true)
    end
end)

--------------------------------------------------------------------------
-- Script UI (Simple English for Japanese VR Users)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 Hide Cockpit (Open Cockpit Mode) ===")
    imgui.text("Enjoy full panoramic VR flight without cockpit interior!")

    imgui.separator()

    local changed, new_val = imgui.checkbox("Hide Cockpit Mesh (No-Cockpit VR View)", hide_cockpit)
    if changed then
        hide_cockpit = new_val
        set_cockpit_visibility(hide_cockpit)
    end

    if imgui.button("Toggle Cockpit Visibility") then
        hide_cockpit = not hide_cockpit
        set_cockpit_visibility(hide_cockpit)
    end
    imgui.same_line()
    imgui.text(hide_cockpit and "[Cockpit: HIDDEN (Open View)]" or "[Cockpit: VISIBLE (Normal)]")

    imgui.separator()
    if imgui.button("Restore Normal Cockpit") then
        hide_cockpit = false
        set_cockpit_visibility(false)
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
