--[[
  ============================================================================
  AerialRefuelToggle.lua : Aerial Refueling 3D UI Toggle Tool
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Purpose:    Toggle display of the Aerial Refueling 3D UI (BP_LiveAerialRefuel3DUIActor)
              Discovered during 3D HUD / Target Marker investigation.
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-REFUEL-UI"

local S = {
    actor  = nil,
    name   = "None",
    hidden = false,
}

local function find_actor()
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    if not actor_class then return end
    local actors = actor_class:get_objects_matching(false) or {}

    for _, a in ipairs(actors) do
        local ok, fn = pcall(function() return a:get_full_name() end)
        if ok and type(fn) == "string" and fn:find("AerialRefuel3DUIActor", 1, true) and not fn:find("Default__", 1, true) then
            S.actor = a
            S.name  = fn:match("([^.]+)$") or fn
            return
        end
    end
end

local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1
    if tick_count % 120 == 0 or not S.actor then
        find_actor()
    end
end)

local function render_ui()
    imgui.text("=== AC8 Aerial Refueling 3D UI Controller ===")
    if S.actor then
        imgui.text_colored("Status: Found (" .. S.name .. ")", 0xFF44FF44)
        local ch, vh = imgui.checkbox("Hide Aerial Refuel UI", S.hidden)
        if ch then
            S.hidden = vh
            pcall(function() S.actor:call("SetActorHiddenInGame", vh) end)
        end
    else
        imgui.text_colored("Status: Not present in current mission", 0xFF888888)
        if imgui.button("Scan Now") then find_actor() end
    end
end

find_actor()

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
