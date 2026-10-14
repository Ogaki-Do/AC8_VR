--[[
  ============================================================================
  ac8_target_marker_scale.lua : Target Marker Customizer (Test Prototype)
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Purpose:    Dynamically scale and customize target markers, lock-on boxes,
              and locator widgets in the cockpit HUD via Lua.
              (Separate custom project from JHMCS visor HUD)

  Features:
    1. Independent Scale & Opacity control for:
       - TargetSelectionDraw (Target Box / Lock-on Box / Tracking Frame)
       - LocatorWidget (Enemy / Target Direction Indicator)
       - Container_WayPoint (Waypoint & Ground Target Container)
       - ExplosivePredication (Bomb/Rocket Impact Reticle)
    2. Center Pivot Guard:
       Sets RenderTransformPivot to (0.5, 0.5) to keep scaling centered.
    3. Safe Child Scaling Mode (Option):
       Scales child image/marker elements instead of the parent canvas
       to prevent screen coordinate shifting.
    4. Diagnostic Dump:
       Exports widget hierarchy to data/ac8_target_marker_dump.txt.
    5. Config Persistence:
       Auto-saves settings to data/ac8_target_marker_config.json.
    6. Script UI:
       Uses clean, simple English for Japanese VR users (no Kanji/Kana font issues).
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME    = "AC8-TGT-SCALE"
local SCRIPT_VER     = "v1.0-proto"
local CFG_FILE       = "data/ac8_target_marker_config.json"
local LOG_FILE       = "data/ac8_target_marker_log.txt"
local DUMP_FILE      = "data/ac8_target_marker_dump.txt"
local SCOPE_NAME     = "WBP_HUD_Chronicle_MainFlight_000_C"

--------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------
local log_handle = nil
do
    local ok, f = pcall(function() return io.open(LOG_FILE, "a") end)
    if ok and f then log_handle = f end
end

local function log_msg(fmt, ...)
    local msg = string.format(fmt, ...)
    print(string.format("[%s] %s", SCRIPT_NAME, msg))
    if log_handle then
        pcall(function()
            log_handle:write(string.format("[%s] %s\n", os.date("%H:%M:%S"), msg))
            log_handle:flush()
        end)
    end
end

log_msg("=== %s %s Loaded ===", SCRIPT_NAME, SCRIPT_VER)

--------------------------------------------------------------------------
-- JSON API Check
--------------------------------------------------------------------------
local HAS_JSON = false
pcall(function() HAS_JSON = (json ~= nil and json.dump_file ~= nil and json.load_file ~= nil) end)

--------------------------------------------------------------------------
-- Target Groups Definition
--------------------------------------------------------------------------
local GROUPS = {
    {
        key         = "target_box",
        label       = "Target Lock-on Box",
        desc        = "Lock-on frame & target selection container",
        patterns    = { "TargetSelectionDraw", "WBP_TargetSelectionDraw" },
        scale       = 1.0,
        scale_x     = 1.0,
        scale_y     = 1.0,
        opacity     = 1.0,
        center_pivot= true,
        scale_child = false,
        active      = true,
        -- Internal runtime cache
        widgets     = {},
        cached_orig = {},
        last_scale  = -1,
        last_op     = -1,
    },
    {
        key         = "locator",
        label       = "Locator / Indicator",
        desc        = "Direction & off-screen target markers",
        patterns    = { "Locator", "WBP_LocatorWidget" },
        scale       = 1.0,
        scale_x     = 1.0,
        scale_y     = 1.0,
        opacity     = 1.0,
        center_pivot= true,
        scale_child = false,
        active      = true,
        widgets     = {},
        cached_orig = {},
        last_scale  = -1,
        last_op     = -1,
    },
    {
        key         = "waypoint",
        label       = "WayPoint / Ground Target",
        desc        = "Mission waypoint & target containers",
        patterns    = { "Container_WayPoint", "WBP_HUD_Container_WayPoint_000", "WayPoint_Panel" },
        scale       = 1.0,
        scale_x     = 1.0,
        scale_y     = 1.0,
        opacity     = 1.0,
        center_pivot= true,
        scale_child = false,
        active      = false,
        widgets     = {},
        cached_orig = {},
        last_scale  = -1,
        last_op     = -1,
    },
    {
        key         = "predication",
        label       = "Bomb / Gun Predication",
        desc        = "Bomb fall & bullet prediction reticle",
        patterns    = { "ExplosivePredication", "WBP_ExplosivePredicationWidget" },
        scale       = 1.0,
        scale_x     = 1.0,
        scale_y     = 1.0,
        opacity     = 1.0,
        center_pivot= true,
        scale_child = false,
        active      = false,
        widgets     = {},
        cached_orig = {},
        last_scale  = -1,
        last_op     = -1,
    },
}

--------------------------------------------------------------------------
-- Config Management (Save / Load)
--------------------------------------------------------------------------
local dirty_config = false
local status_ui_msg = "Ready"

local function save_config()
    local data = {}
    for _, g in ipairs(GROUPS) do
        data[g.key] = {
            scale        = g.scale,
            scale_x      = g.scale_x,
            scale_y      = g.scale_y,
            opacity      = g.opacity,
            center_pivot = g.center_pivot,
            scale_child  = g.scale_child,
            active       = g.active,
        }
    end

    if HAS_JSON then
        local ok = pcall(function() json.dump_file(CFG_FILE, data, 4) end)
        if ok then
            dirty_config = false
            status_ui_msg = "Saved successfully!"
            log_msg("Config saved to %s", CFG_FILE)
            return true
        end
    end

    -- Fallback simple text save
    local ok, f = pcall(function() return io.open(CFG_FILE .. ".txt", "w") end)
    if ok and f then
        for _, g in ipairs(GROUPS) do
            f:write(string.format("[%s]\n", g.key))
            f:write(string.format("scale=%.3f\n", g.scale))
            f:write(string.format("opacity=%.3f\n", g.opacity))
            f:write(string.format("center_pivot=%s\n", tostring(g.center_pivot)))
            f:write(string.format("scale_child=%s\n", tostring(g.scale_child)))
            f:write(string.format("active=%s\n\n", tostring(g.active)))
        end
        f:close()
        dirty_config = false
        status_ui_msg = "Saved (TXT fallback)!"
        log_msg("Config saved to %s.txt", CFG_FILE)
        return true
    end

    status_ui_msg = "Save Failed!"
    return false
end

local function load_config()
    if HAS_JSON then
        local ok, data = pcall(function() return json.load_file(CFG_FILE) end)
        if ok and type(data) == "table" then
            for _, g in ipairs(GROUPS) do
                local d = data[g.key]
                if d and type(d) == "table" then
                    if type(d.scale) == "number" then g.scale = d.scale end
                    if type(d.scale_x) == "number" then g.scale_x = d.scale_x end
                    if type(d.scale_y) == "number" then g.scale_y = d.scale_y end
                    if type(d.opacity) == "number" then g.opacity = d.opacity end
                    if type(d.center_pivot) == "boolean" then g.center_pivot = d.center_pivot end
                    if type(d.scale_child) == "boolean" then g.scale_child = d.scale_child end
                    if type(d.active) == "boolean" then g.active = d.active end
                    g.last_scale = -1
                    g.last_op = -1
                end
            end
            log_msg("Config loaded from %s", CFG_FILE)
            return true
        end
    end
    return false
end

local function reset_all_defaults()
    for _, g in ipairs(GROUPS) do
        g.scale        = 1.0
        g.scale_x      = 1.0
        g.scale_y      = 1.0
        g.opacity      = 1.0
        g.center_pivot = true
        g.scale_child  = false
        g.active       = (g.key == "target_box" or g.key == "locator")
        g.last_scale   = -1
        g.last_op      = -1
    end
    dirty_config = true
    status_ui_msg = "Reset to Defaults"
    log_msg("All groups reset to default")
end

--------------------------------------------------------------------------
-- Widget Utility Functions
--------------------------------------------------------------------------
local widget_classes = {}
local function init_classes()
    if #widget_classes > 0 then return end
    for _, path in ipairs({ "Class /Script/UMG.UserWidget",
                            "Class /Script/UMG.Widget",
                            "Class /Script/UMG.CanvasPanel" }) do
        local ok, c = pcall(function() return api:find_uobject(path) end)
        if ok and c ~= nil then
            table.insert(widget_classes, c)
        end
    end
end

local function get_safe_name(obj)
    if not obj then return "" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or ""
end

local function get_children_recursive(w, max_depth, current_depth)
    current_depth = current_depth or 0
    if not w or current_depth >= (max_depth or 5) then return {} end
    local results = {}
    local ok_cnt, count = pcall(function() return w.GetChildrenCount and w:GetChildrenCount() or 0 end)
    if ok_cnt and type(count) == "number" and count > 0 then
        for i = 0, count - 1 do
            local ok_ch, child = pcall(function() return w:GetChildAt(i) end)
            if ok_ch and child ~= nil then
                table.insert(results, child)
                local sub = get_children_recursive(child, max_depth, current_depth + 1)
                for _, s in ipairs(sub) do table.insert(results, s) end
            end
        end
    end
    return results
end

--------------------------------------------------------------------------
-- Flight & MainFlight HUD Detection
--------------------------------------------------------------------------
local current_pawn = nil
local current_mainflight = nil
local flight_active = false
local tick_count = 0

local function check_flight_active(force)
    tick_count = tick_count + 1
    if not force and (tick_count % 30 ~= 0) and current_mainflight ~= nil then
        return flight_active
    end

    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    if not pawn then
        flight_active = false
        current_pawn = nil
        current_mainflight = nil
        return false
    end

    local pname = get_safe_name(pawn)
    if pname:find("Hangar", 1, true) or pname:find("Menu", 1, true) or pname:find("DefaultPawn", 1, true) then
        flight_active = false
        current_pawn = nil
        current_mainflight = nil
        return false
    end

    current_pawn = pawn
    flight_active = true
    return true
end

--------------------------------------------------------------------------
-- Widget Search & Binding
--------------------------------------------------------------------------
local function search_group_widgets(group)
    init_classes()
    local found = {}
    local seen_names = {}

    for _, cls in ipairs(widget_classes) do
        local ok, objs = pcall(function() return cls:get_objects_matching(false) end)
        if ok and type(objs) == "table" then
            for _, obj in ipairs(objs) do
                local fullname = get_safe_name(obj)
                -- Only runtime instances inside MainFlight HUD (exclude Pause Menu duplicates)
                if fullname:find("/Engine/Transient", 1, true)
                   and (fullname:find(SCOPE_NAME, 1, true) or fullname:find("MainFlight", 1, true))
                   and not seen_names[fullname] then

                    for _, pat in ipairs(group.patterns) do
                        if fullname:find(pat, 1, true) then
                            seen_names[fullname] = true
                            table.insert(found, obj)
                            break
                        end
                    end
                end
            end
        end
    end

    group.widgets = found
    log_msg("Group '%s' found %d widgets", group.label, #found)
    return found
end

local function scan_all_groups()
    if not check_flight_active(true) then
        for _, g in ipairs(GROUPS) do g.widgets = {} end
        return
    end

    for _, g in ipairs(GROUPS) do
        search_group_widgets(g)
    end
end

--------------------------------------------------------------------------
-- Apply Scale & Transform
--------------------------------------------------------------------------
local function apply_widget_scale(w, sc_x, sc_y, center_pivot)
    if not w then return end
    pcall(function()
        if center_pivot then
            -- Set pivot to center (0.5, 0.5) so it scales from the center
            w:call("SetRenderTransformPivot", { X = 0.5, Y = 0.5 })
        end
        w:call("SetRenderScale", { X = sc_x, Y = sc_y })
    end)
end

local function apply_widget_opacity(w, op)
    if not w then return end
    pcall(function()
        w:call("SetRenderOpacity", op)
    end)
end

local function apply_group(g)
    if not flight_active or #g.widgets == 0 then return end
    if not g.active then return end

    local final_sx = g.scale * g.scale_x
    local final_sy = g.scale * g.scale_y
    local op       = g.opacity

    -- Check if modified
    local scale_changed = (math.abs((g.last_scale or -1) - final_sx) > 0.001)
                       or (math.abs((g.last_scale_y or -1) - final_sy) > 0.001)
    local op_changed    = (math.abs((g.last_op or -1) - op) > 0.001)

    if not scale_changed and not op_changed then
        return
    end

    g.last_scale   = final_sx
    g.last_scale_y = final_sy
    g.last_op      = op

    for _, w in ipairs(g.widgets) do
        if g.scale_child then
            -- Mode B: Scale child leaf widgets to avoid moving screen coordinates
            local children = get_children_recursive(w, 4)
            for _, ch in ipairs(children) do
                if scale_changed then
                    apply_widget_scale(ch, final_sx, final_sy, g.center_pivot)
                end
                if op_changed then
                    apply_widget_opacity(ch, op)
                end
            end
        else
            -- Mode A: Scale the widget itself
            if scale_changed then
                apply_widget_scale(w, final_sx, final_sy, g.center_pivot)
            end
            if op_changed then
                apply_widget_opacity(w, op)
            end
        end
    end
end

--------------------------------------------------------------------------
-- Hierarchy Dump Feature (Diagnostic)
--------------------------------------------------------------------------
local function dump_marker_hierarchy()
    local ok, f = pcall(function() return io.open(DUMP_FILE, "w") end)
    if not ok or not f then
        status_ui_msg = "Dump failed: cannot open file"
        return
    end

    f:write("====================================================================\n")
    f:write(string.format("  ACE COMBAT 8 - Target Marker Widget Dump (%s)\n", os.date("%Y-%m-%d %H:%M:%S")))
    f:write("====================================================================\n\n")

    for _, g in ipairs(GROUPS) do
        f:write(string.format("【Group: %s】 Found: %d instances\n", g.label, #g.widgets))
        for idx, w in ipairs(g.widgets) do
            local fn = get_safe_name(w)
            local vis = "unknown"
            pcall(function() vis = tostring(w:call("GetVisibility")) end)
            f:write(string.format("  [%02d] %s (Vis: %s)\n", idx, fn, vis))

            -- Dump children
            local children = get_children_recursive(w, 5)
            f:write(string.format("       Children count: %d\n", #children))
            for cidx, ch in ipairs(children) do
                local cfn = get_safe_name(ch)
                local short = cfn:match("([^.]+)$") or cfn
                f:write(string.format("         -> [%02d] %s\n", cidx, short))
            end
        end
        f:write("\n")
    end

    f:write("====================================================================\n")
    f:write("Dump Complete.\n")
    f:close()

    status_ui_msg = "Hierarchy Dumped to " .. DUMP_FILE
    log_msg("Widget hierarchy dumped to %s", DUMP_FILE)
end

--------------------------------------------------------------------------
-- Main Tick Callback
--------------------------------------------------------------------------
local rescan_counter = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    if not check_flight_active(false) then return end

    rescan_counter = rescan_counter + 1
    if rescan_counter % 300 == 0 then
        -- Periodic lightweight check for missing widgets
        for _, g in ipairs(GROUPS) do
            if #g.widgets == 0 and g.active then
                search_group_widgets(g)
            end
        end
    end

    for _, g in ipairs(GROUPS) do
        apply_group(g)
    end
end)

--------------------------------------------------------------------------
-- Script UI (ImGui) - Simple English for Japanese VR Users
--------------------------------------------------------------------------
local function draw_preset_buttons(g)
    -- Preset Size Buttons
    imgui.text("Presets:")
    imgui.same_line()
    if imgui.button("Small (0.7x)##" .. g.key) then
        g.scale = 0.70; dirty_config = true; g.last_scale = -1
    end
    imgui.same_line()
    if imgui.button("Default (1.0x)##" .. g.key) then
        g.scale = 1.00; g.scale_x = 1.0; g.scale_y = 1.0; dirty_config = true; g.last_scale = -1
    end
    imgui.same_line()
    if imgui.button("Big (1.4x)##" .. g.key) then
        g.scale = 1.40; dirty_config = true; g.last_scale = -1
    end
    imgui.same_line()
    if imgui.button("Huge (2.0x)##" .. g.key) then
        g.scale = 2.00; dirty_config = true; g.last_scale = -1
    end
end

local function render_ui()
    imgui.text("=== AC8 Target Marker Scaler " .. SCRIPT_VER .. " ===")
    
    local stat_str = flight_active and "[Active (In Flight)]" or "[Inactive (Menu/Loading)]"
    imgui.text("Flight HUD Status: " .. stat_str)

    if imgui.button("Rescan Widgets (Search HUD)") then
        scan_all_groups()
        status_ui_msg = "Rescanned HUD widgets"
    end
    imgui.same_line()
    if imgui.button("Dump Hierarchy (Log to File)") then
        dump_marker_hierarchy()
    end

    imgui.separator()

    for _, g in ipairs(GROUPS) do
        local head_text = string.format("%s [Found: %d]", g.label, #g.widgets)
        
        -- Active toggle checkbox
        local c_act, v_act = imgui.checkbox("Enable##" .. g.key, g.active)
        if c_act then g.active = v_act; dirty_config = true; g.last_scale = -1 end
        imgui.same_line()
        imgui.text(head_text)

        if g.active then
            -- Main Scale Slider (0.2x to 3.0x)
            local cs, vs = imgui.slider_float("Size (Scale)##" .. g.key, g.scale, 0.20, 3.00)
            if cs then g.scale = vs; dirty_config = true; g.last_scale = -1 end

            -- Aspect Width / Height微調整 (Optional 0.5 to 2.0)
            local csx, vsx = imgui.slider_float("Aspect Width (X)##" .. g.key, g.scale_x, 0.50, 2.00)
            if csx then g.scale_x = vsx; dirty_config = true; g.last_scale = -1 end

            local csy, vsy = imgui.slider_float("Aspect Height (Y)##" .. g.key, g.scale_y, 0.50, 2.00)
            if csy then g.scale_y = vsy; dirty_config = true; g.last_scale = -1 end

            -- Opacity Slider
            local co, vo = imgui.slider_float("Opacity (Alpha)##" .. g.key, g.opacity, 0.0, 1.0)
            if co then g.opacity = vo; dirty_config = true; g.last_op = -1 end

            -- Preset Buttons
            draw_preset_buttons(g)

            -- Advanced Scaling Modes
            local cp, vp = imgui.checkbox("Center Pivot Guard (Keep Centered)##" .. g.key, g.center_pivot)
            if cp then g.center_pivot = vp; dirty_config = true; g.last_scale = -1 end

            local cc, vc = imgui.checkbox("Safe Child Mode (Scale Icons Only)##" .. g.key, g.scale_child)
            if cc then g.scale_child = vc; dirty_config = true; g.last_scale = -1 end
            pcall(function() imgui.text_disabled(" *Safe Child Mode: Scales icons inside to prevent position offset") end)

            imgui.separator()
        end
    end

    -- Bottom Controls
    if imgui.button("Save Settings") then
        save_config()
    end
    imgui.same_line()
    if imgui.button("Reset All to Default") then
        reset_all_defaults()
    end

    if dirty_config then
        imgui.same_line()
        pcall(function() imgui.text_colored(" [Unsaved Changes]", 0xFF44CCFF) end)
    end

    if status_ui_msg ~= "" then
        imgui.text("Status: " .. status_ui_msg)
    end
end

-- Register UI Callback safely
if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

--------------------------------------------------------------------------
-- Initial Setup
--------------------------------------------------------------------------
load_config()
scan_all_groups()

log_msg("Initialization complete. ScriptUI ready.")
