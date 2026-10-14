--[[
  ============================================================================
  HIDEandSHOWallHUD.lua : MainFlight HUD Toggle & All-Elements Unlocker
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Feature:    Toggles the 2D MainFlight HUD on and off.
              Turning it OFF (Collapsed) and then back ON triggers an engine
              state where ALL hidden HUD elements, full gauges, and hidden icons
              become visible all at once! (formerly TEST 5 in investigations).

  Usage:      Press Insert -> ScriptUI -> Click "Instant HIDE & SHOW ALL"
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "HIDEandSHOWallHUD"
local hud_hidden  = false

local function get_safe_name(obj)
    if not obj then return "" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or ""
end

local function find_mainflight_widgets()
    local umg_class = api:find_uobject("Class /Script/UMG.Widget")
    if not umg_class then return {} end
    local objs = umg_class:get_objects_matching(false) or {}
    local out = {}
    for _, w in ipairs(objs) do
        local fn = get_safe_name(w)
        if fn:find("/Engine/Transient", 1, true) and fn:find("MainFlight", 1, true) then
            table.insert(out, w)
        end
    end
    return out
end

local function set_hud_visibility(hide)
    local widgets = find_mainflight_widgets()
    local vis_code = hide and 1 or 4 -- 1 = Collapsed (Hide), 4 = SelfHitTestInvisible (Show)
    for _, w in ipairs(widgets) do
        pcall(function() w:call("SetVisibility", vis_code) end)
    end
end

-- Instant HIDE & SHOW ALL sequence
local trigger_instant_cycle = false
local cycle_frame = 0

uevr.sdk.callbacks.on_post_engine_tick(function()
    if trigger_instant_cycle then
        cycle_frame = cycle_frame + 1
        if cycle_frame == 1 then
            -- Frame 1: Collapse (Turn OFF)
            set_hud_visibility(true)
        elseif cycle_frame >= 4 then
            -- Frame 4: Restore Visible (Turn ON -> All hidden elements awaken!)
            set_hud_visibility(false)
            trigger_instant_cycle = false
            cycle_frame = 0
            hud_hidden = false
        end
    end
end)

--------------------------------------------------------------------------
-- Script UI (Simple English for Japanese VR Users)
--------------------------------------------------------------------------
local function render_ui()
    imgui.text("=== AC8 HIDE & SHOW ALL HUD ===")
    imgui.text("Turning HUD OFF then ON unlocks ALL hidden HUD elements!")

    imgui.separator()

    -- One-click magic button
    if imgui.button(">> Instant HIDE & SHOW ALL (Unlock All Elements) <<") then
        trigger_instant_cycle = true
        cycle_frame = 0
    end

    imgui.separator()

    -- Manual Controls
    local changed, new_val = imgui.checkbox("Hide MainFlight HUD (Turn OFF)", hud_hidden)
    if changed then
        hud_hidden = new_val
        set_hud_visibility(hud_hidden)
    end

    if imgui.button("Turn HUD ON (Restore)") then
        hud_hidden = false
        set_hud_visibility(false)
    end
    imgui.same_line()
    if imgui.button("Turn HUD OFF (Hide)") then
        hud_hidden = true
        set_hud_visibility(true)
    end

    imgui.separator()
    imgui.text(hud_hidden and "Current Status: [HUD is HIDDEN]" or "Current Status: [HUD is ACTIVE / ALL SHOWN]")
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully.", SCRIPT_NAME))
