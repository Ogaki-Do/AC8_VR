--[[
  ============================================================================
  ac8_target_locator_diff_hunter.lua : Off-Screen Target Indicator Diff Hunter
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Purpose:    Capture snapshots of the entire game world (3D Actors, 3D Components,
              and 2D/3D UMG Widgets) under two distinct states:
                State A: Target is ON-SCREEN (or unlocked / idle - No Arrow needed)
                State B: Target is OFF-SCREEN (locked - "TGT" Arrow IS visible)
              Then perform a deep differential comparison (Diff) to uncover:
                1. Text hits ("TGT", "MQ-99", Target Call signs)
                2. Newly spawned 3D Actors / Components / Widgets
                3. Objects that flipped from Hidden/Collapsed to Visible
                4. Objects with significant rotation/position changes (pointing to target)
                5. Priority watch-list for Target/Locator/3DUI/Billboard/Pin objects
  Safety:     100% Pure ASCII, Zero-Tick Scanning (Captures ONLY on button click),
              Game-Thread safe, Crash-Free.
  Output:     data/ac8_locator_diff_report.txt
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-Target-Locator-Diff-Hunter"
local REPORT_FILE = "data/ac8_locator_diff_report.txt"

local function safe_call(fn, default)
    local ok, res = pcall(fn)
    return ok and res or default
end

local function get_safe_name(obj)
    if not obj then return "nil" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or tostring(obj)
end

local function get_safe_class_name(obj)
    if not obj then return "unknown" end
    local ok, c = pcall(function() return obj:get_class():get_name() end)
    return (ok and type(c) == "string") and c or "unknown"
end

local function get_short_name(obj)
    local fn = get_safe_name(obj)
    return fn:match("([^.]+)$") or fn
end

-- -----------------------------------------------------------------------------
-- Keywords for Special Watchlist & Target Text Matching
-- -----------------------------------------------------------------------------
local WATCH_KEYWORDS = {
    "target", "locator", "arrow", "offscreen", "pointer", "seeker",
    "livetarget", "livemainhud", "3dui", "billboard", "indicator",
    "container", "mark", "reticle", "guid", "tgt", "pin", "nexttarget",
    "objecttype", "uiarrow"
}

local function matches_watchlist(str)
    if not str then return false end
    local lower = str:lower()
    for _, kw in ipairs(WATCH_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

-- -----------------------------------------------------------------------------
-- Snapshot Data Containers
-- -----------------------------------------------------------------------------
local SnapshotA = nil
local SnapshotB = nil
local DiffSummary = {
    text_hits       = 0,
    new_actors      = 0,
    new_comps       = 0,
    new_widgets     = 0,
    vis_actors      = 0,
    vis_comps       = 0,
    vis_widgets     = 0,
    watched_changes = 0,
    compared_time   = nil,
    report_path     = nil,
}

-- -----------------------------------------------------------------------------
-- Capture Engine (Executed ONLY on button click in game thread)
-- -----------------------------------------------------------------------------
local function capture_current_state(state_name)
    local snap = {
        name        = state_name,
        time        = os.date("%Y-%m-%d %H:%M:%S"),
        actors      = {}, -- map: full_name -> { obj, name, class, loc, rot, bHidden, bHiddenInGame }
        components  = {}, -- map: full_name -> { obj, name, class, bVisible, rel_loc, rel_rot, text }
        widgets     = {}, -- map: full_name -> { obj, name, class, vis, op, tx, ty, angle, in_vp, text }
    }

    -- 1. Capture 3D Actors
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    if actor_class then
        local all_acts = safe_call(function() return actor_class:get_objects_matching(false) end, {})
        for _, a in ipairs(all_acts) do
            local fn = get_safe_name(a)
            if not fn:find("Default__", 1, true) then
                local sn = get_short_name(a)
                local cn = get_safe_class_name(a)

                local lx, ly, lz = 0.0, 0.0, 0.0
                pcall(function()
                    local loc = a:call("K2_GetActorLocation")
                    if loc then lx, ly, lz = loc.X or 0, loc.Y or 0, loc.Z or 0 end
                end)

                local pitch, yaw, roll = 0.0, 0.0, 0.0
                pcall(function()
                    local rot = a:call("K2_GetActorRotation")
                    if rot then pitch, yaw, roll = rot.Pitch or 0, rot.Yaw or 0, rot.Roll or 0 end
                end)

                local b_hid = safe_call(function() return a.bHidden end, false)
                local b_hid_in_game = safe_call(function() return a.bHiddenInGame end, false)

                snap.actors[fn] = {
                    name         = sn,
                    class        = cn,
                    full         = fn,
                    lx           = lx, ly = ly, lz = lz,
                    pitch        = pitch, yaw = yaw, roll = roll,
                    bHidden      = (b_hid == true),
                    bHiddenInGame= (b_hid_in_game == true),
                }
            end
        end
    end

    -- 2. Capture Scene / Actor Components
    local comp_class = api:find_uobject("Class /Script/Engine.SceneComponent")
    if comp_class then
        local all_comps = safe_call(function() return comp_class:get_objects_matching(false) end, {})
        for _, c in ipairs(all_comps) do
            local fn = get_safe_name(c)
            if not fn:find("Default__", 1, true) then
                local sn = get_short_name(c)
                local cn = get_safe_class_name(c)

                local r_lx, r_ly, r_lz = 0.0, 0.0, 0.0
                local r_pitch, r_yaw, r_roll = 0.0, 0.0, 0.0
                pcall(function()
                    local loc = c.RelativeLocation
                    if loc then r_lx, r_ly, r_lz = loc.X or 0, loc.Y or 0, loc.Z or 0 end
                    local rot = c.RelativeRotation
                    if rot then r_pitch, r_yaw, r_roll = rot.Pitch or 0, rot.Yaw or 0, rot.Roll or 0 end
                end)

                local b_vis = safe_call(function() return c.bVisible end, true)
                local b_hid_game = safe_call(function() return c.bHiddenInGame end, false)

                -- Extract component text if available (TextRenderComponent etc.)
                local text_val = ""
                pcall(function()
                    local tv = c.Text or c:call("GetText")
                    if tv then text_val = tostring(tv) end
                end)

                snap.components[fn] = {
                    name         = sn,
                    class        = cn,
                    full         = fn,
                    lx           = r_lx, ly = r_ly, lz = r_lz,
                    pitch        = r_pitch, yaw = r_yaw, roll = r_roll,
                    bVisible     = (b_vis == true),
                    bHiddenInGame= (b_hid_game == true),
                    text         = text_val,
                }
            end
        end
    end

    -- 3. Capture UMG Widgets
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if widget_class then
        local all_widgets = safe_call(function() return widget_class:get_objects_matching(false) end, {})
        for _, w in ipairs(all_widgets) do
            local fn = get_safe_name(w)
            if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
                local sn = get_short_name(w)
                local cn = get_safe_class_name(w)

                local vis = safe_call(function() return w:GetVisibility() end, -1)
                local op  = safe_call(function() return w.RenderOpacity end, 1.0)
                local tx, ty = 0.0, 0.0
                local angle = 0.0
                pcall(function()
                    local t = w:GetRenderTranslation()
                    if t then tx, ty = t.X or 0, t.Y or 0 end
                    angle = w:GetRenderTransformAngle() or 0.0
                end)

                local in_vp = false
                pcall(function() in_vp = w:call("IsInViewport") end)

                -- Extract widget text if available (TextBlock, LiveLocalizeTextBlock)
                local text_val = ""
                pcall(function()
                    local tv = w.Text or w:call("GetText")
                    if tv then text_val = tostring(tv) end
                end)

                snap.widgets[fn] = {
                    name         = sn,
                    class        = cn,
                    full         = fn,
                    vis          = vis,
                    op           = op,
                    tx           = tx, ty = ty,
                    angle        = angle,
                    in_viewport  = (in_vp == true),
                    text         = text_val,
                }
            end
        end
    end

    return snap
end

-- -----------------------------------------------------------------------------
-- Differential Comparison & Deep Report Generator
-- -----------------------------------------------------------------------------
local function compare_snapshots_and_write_report()
    if not SnapshotA or not SnapshotB then return end

    local f = io.open(REPORT_FILE, "w")
    if not f then return end

    local now = os.date("%Y-%m-%d %H:%M:%S")
    f:write("========================================================================================\n")
    f:write("  ACE COMBAT 8 : OFF-SCREEN TARGET LOCATOR DIFFERENTIAL COMPARISON REPORT\n")
    f:write(string.format("  Generated Time: %s\n", now))
    f:write(string.format("  State A [ON-SCREEN / IDLE] : Captured %s\n", SnapshotA.time))
    f:write(string.format("  State B [OFF-SCREEN / ARROW] : Captured %s\n", SnapshotB.time))
    f:write("========================================================================================\n\n")

    -- Reset counters
    DiffSummary = {
        text_hits       = 0,
        new_actors      = 0,
        new_comps       = 0,
        new_widgets     = 0,
        vis_actors      = 0,
        vis_comps       = 0,
        vis_widgets     = 0,
        watched_changes = 0,
        compared_time   = now,
        report_path     = REPORT_FILE,
    }

    local sec_text_hits = {}
    local sec_watched = {}
    local sec_new_actors = {}
    local sec_new_comps = {}
    local sec_new_widgets = {}
    local sec_vis_changes = {}
    local sec_transform_changes = {}

    -- -------------------------------------------------------------------------
    -- 1. Compare 3D Actors
    -- -------------------------------------------------------------------------
    for fn_b, b in pairs(SnapshotB.actors) do
        local a = SnapshotA.actors[fn_b]
        local is_watched = matches_watchlist(b.name) or matches_watchlist(b.class) or matches_watchlist(fn_b)

        if not a then
            -- NEW in State B
            DiffSummary.new_actors = DiffSummary.new_actors + 1
            local line = string.format("[NEW ACTOR] %-30s | Class: %-25s | Loc: (%.1f, %.1f, %.1f) | Hid: %s/%s\n     Path: %s",
                b.name, b.class, b.lx, b.ly, b.lz, tostring(b.bHidden), tostring(b.bHiddenInGame), fn_b)
            table.insert(sec_new_actors, line)
            if is_watched then
                table.insert(sec_watched, "★ " .. line)
                DiffSummary.watched_changes = DiffSummary.watched_changes + 1
            end
        else
            -- Check Visibility change (Hidden in A -> Visible in B)
            local a_hidden = a.bHidden or a.bHiddenInGame
            local b_hidden = b.bHidden or b.bHiddenInGame
            if a_hidden and not b_hidden then
                DiffSummary.vis_actors = DiffSummary.vis_actors + 1
                local line = string.format("[ACTOR BECAME VISIBLE] %-30s | Class: %-25s | Loc: (%.1f, %.1f, %.1f)\n     Path: %s",
                    b.name, b.class, b.lx, b.ly, b.lz, fn_b)
                table.insert(sec_vis_changes, line)
                if is_watched then
                    table.insert(sec_watched, "★ " .. line)
                    DiffSummary.watched_changes = DiffSummary.watched_changes + 1
                end
            end

            -- Check Significant Rotation or Position Shift
            local d_loc = math.sqrt((b.lx - a.lx)^2 + (b.ly - a.ly)^2 + (b.lz - a.lz)^2)
            local d_rot = math.abs(b.yaw - a.yaw) + math.abs(b.pitch - a.pitch)
            if d_rot > 15.0 or (is_watched and d_loc > 10.0) then
                local line = string.format("[ACTOR TRANSFORM SHIFT] %-30s | Rot: (%.1f, %.1f) -> (%.1f, %.1f) | dLoc: %.1f\n     Path: %s",
                    b.name, a.pitch, a.yaw, b.pitch, b.yaw, d_loc, fn_b)
                table.insert(sec_transform_changes, line)
                if is_watched then
                    table.insert(sec_watched, "★ " .. line)
                    DiffSummary.watched_changes = DiffSummary.watched_changes + 1
                end
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- 2. Compare 3D Components
    -- -------------------------------------------------------------------------
    for fn_b, b in pairs(SnapshotB.components) do
        local a = SnapshotA.components[fn_b]
        local is_watched = matches_watchlist(b.name) or matches_watchlist(b.class) or matches_watchlist(fn_b)

        -- Check Text Hits (TGT, MQ-99, etc.)
        if b.text and #b.text > 0 then
            local t_upper = b.text:upper()
            if t_upper:find("TGT", 1, true) or t_upper:find("MQ-", 1, true) or t_upper:find("TARGET", 1, true) then
                local line = string.format("[COMPONENT TEXT MATCH] '%s' | Name: %s | Class: %s\n     Path: %s",
                    b.text, b.name, b.class, fn_b)
                table.insert(sec_text_hits, line)
                DiffSummary.text_hits = DiffSummary.text_hits + 1
            end
        end

        if not a then
            -- NEW in State B
            DiffSummary.new_comps = DiffSummary.new_comps + 1
            local line = string.format("[NEW COMPONENT] %-30s | Class: %-25s | Vis: %s | Loc: (%.1f, %.1f, %.1f)\n     Path: %s",
                b.name, b.class, tostring(b.bVisible), b.lx, b.ly, b.lz, fn_b)
            table.insert(sec_new_comps, line)
            if is_watched then
                table.insert(sec_watched, "★ " .. line)
                DiffSummary.watched_changes = DiffSummary.watched_changes + 1
            end
        else
            -- Check Visibility change (Invisible in A -> Visible in B)
            if not a.bVisible and b.bVisible then
                DiffSummary.vis_comps = DiffSummary.vis_comps + 1
                local line = string.format("[COMPONENT BECAME VISIBLE] %-30s | Class: %-25s | RelLoc: (%.1f, %.1f, %.1f)\n     Path: %s",
                    b.name, b.class, b.lx, b.ly, b.lz, fn_b)
                table.insert(sec_vis_changes, line)
                if is_watched then
                    table.insert(sec_watched, "★ " .. line)
                    DiffSummary.watched_changes = DiffSummary.watched_changes + 1
                end
            end

            -- Check Rotation Shift
            local d_rot = math.abs(b.yaw - a.yaw) + math.abs(b.pitch - a.pitch)
            if d_rot > 15.0 then
                local line = string.format("[COMPONENT ROTATION SHIFT] %-30s | Rot: (%.1f, %.1f) -> (%.1f, %.1f)\n     Path: %s",
                    b.name, a.pitch, a.yaw, b.pitch, b.yaw, fn_b)
                table.insert(sec_transform_changes, line)
                if is_watched then
                    table.insert(sec_watched, "★ " .. line)
                    DiffSummary.watched_changes = DiffSummary.watched_changes + 1
                end
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- 3. Compare UMG Widgets
    -- -------------------------------------------------------------------------
    for fn_b, b in pairs(SnapshotB.widgets) do
        local a = SnapshotA.widgets[fn_b]
        local is_watched = matches_watchlist(b.name) or matches_watchlist(b.class) or matches_watchlist(fn_b)

        -- Check Text Hits (TGT, MQ-99, etc.)
        if b.text and #b.text > 0 then
            local t_upper = b.text:upper()
            if t_upper:find("TGT", 1, true) or t_upper:find("MQ-", 1, true) or t_upper:find("TARGET", 1, true) then
                local line = string.format("[WIDGET TEXT MATCH] '%s' | Name: %s | Vis: %d | Op: %.2f | RT: (%.1f, %.1f)\n     Path: %s",
                    b.text, b.name, b.vis, b.op, b.tx, b.ty, fn_b)
                table.insert(sec_text_hits, line)
                DiffSummary.text_hits = DiffSummary.text_hits + 1
            end
        end

        if not a then
            -- NEW in State B
            DiffSummary.new_widgets = DiffSummary.new_widgets + 1
            local line = string.format("[NEW WIDGET] %-30s | Class: %-25s | Vis: %d | Op: %.2f | RT: (%.1f, %.1f)\n     Path: %s",
                b.name, b.class, b.vis, b.op, b.tx, b.ty, fn_b)
            table.insert(sec_new_widgets, line)
            if is_watched then
                table.insert(sec_watched, "★ " .. line)
                DiffSummary.watched_changes = DiffSummary.watched_changes + 1
            end
        else
            -- Check Visibility change (Hidden/Collapsed in A -> Visible in B or Opacity 0 -> >0)
            local a_vis = (a.vis == 0 or a.vis == 3 or a.vis == 4) and (a.op > 0.05)
            local b_vis = (b.vis == 0 or b.vis == 3 or b.vis == 4) and (b.op > 0.05)
            if not a_vis and b_vis then
                DiffSummary.vis_widgets = DiffSummary.vis_widgets + 1
                local line = string.format("[WIDGET BECAME VISIBLE] %-30s | Vis: %d->%d | Op: %.2f->%.2f | RT: (%.1f, %.1f) | Ang: %.1f\n     Path: %s",
                    b.name, a.vis, b.vis, a.op, b.op, b.tx, b.ty, b.angle, fn_b)
                table.insert(sec_vis_changes, line)
                if is_watched then
                    table.insert(sec_watched, "★ " .. line)
                    DiffSummary.watched_changes = DiffSummary.watched_changes + 1
                end
            end

            -- Check Angle or Position Shift
            local d_ang = math.abs(b.angle - a.angle)
            local d_tx = math.abs(b.tx - a.tx)
            local d_ty = math.abs(b.ty - a.ty)
            if d_ang > 15.0 or (is_watched and (d_tx > 20.0 or d_ty > 20.0)) then
                local line = string.format("[WIDGET TRANSFORM SHIFT] %-30s | Ang: %.1f->%.1f | RT: (%.1f, %.1f)->(%.1f, %.1f)\n     Path: %s",
                    b.name, a.angle, b.angle, a.tx, a.ty, b.tx, b.ty, fn_b)
                table.insert(sec_transform_changes, line)
                if is_watched then
                    table.insert(sec_watched, "★ " .. line)
                    DiffSummary.watched_changes = DiffSummary.watched_changes + 1
                end
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- Write Output Sections
    -- -------------------------------------------------------------------------

    -- SECTION 0: DIRECT TEXT HITS ("TGT", "MQ-99", Target names)
    f:write("########################################################################################\n")
    f:write(string.format("  【DIRECT TEXT MATCHES: 'TGT' or Target Name (Total: %d)】\n", #sec_text_hits))
    f:write("  (These objects literally contain 'TGT' or 'MQ-99' text on screen!)\n")
    f:write("########################################################################################\n")
    if #sec_text_hits == 0 then
        f:write("  (No direct text content matched)\n\n")
    else
        for _, l in ipairs(sec_text_hits) do f:write(l .. "\n\n") end
    end

    -- SECTION 1: WATCHLIST HIGHLIGHTS
    f:write("########################################################################################\n")
    f:write(string.format("  【PRIORITY WATCHLIST HIGHLIGHTS (Total: %d)】\n", #sec_watched))
    f:write("  (Objects matching 'Target', 'Locator', 'Arrow', 'Pointer', '3DUI', etc. with state changes)\n")
    f:write("########################################################################################\n")
    if #sec_watched == 0 then
        f:write("  (No direct keyword hits changed between State A and State B)\n\n")
    else
        for _, l in ipairs(sec_watched) do f:write(l .. "\n\n") end
    end

    -- SECTION 2: BECAME VISIBLE
    f:write("----------------------------------------------------------------------------------------\n")
    f:write(string.format("  【SECTION 2: OBJECTS THAT BECAME VISIBLE IN STATE B (Total: %d)】\n", #sec_vis_changes))
    f:write("----------------------------------------------------------------------------------------\n")
    if #sec_vis_changes == 0 then
        f:write("  (None)\n\n")
    else
        for _, l in ipairs(sec_vis_changes) do f:write(l .. "\n\n") end
    end

    -- SECTION 3: NEWLY SPAWNED 3D ACTORS
    f:write("----------------------------------------------------------------------------------------\n")
    f:write(string.format("  【SECTION 3: NEWLY SPAWNED 3D ACTORS (Total: %d)】\n", #sec_new_actors))
    f:write("----------------------------------------------------------------------------------------\n")
    if #sec_new_actors == 0 then
        f:write("  (None)\n\n")
    else
        for _, l in ipairs(sec_new_actors) do f:write(l .. "\n\n") end
    end

    -- SECTION 4: NEWLY CREATED 3D COMPONENTS
    f:write("----------------------------------------------------------------------------------------\n")
    f:write(string.format("  【SECTION 4: NEWLY CREATED 3D COMPONENTS (Total: %d)】\n", #sec_new_comps))
    f:write("----------------------------------------------------------------------------------------\n")
    if #sec_new_comps == 0 then
        f:write("  (None)\n\n")
    else
        for _, l in ipairs(sec_new_comps) do f:write(l .. "\n\n") end
    end

    -- SECTION 5: NEWLY CREATED UMG WIDGETS
    f:write("----------------------------------------------------------------------------------------\n")
    f:write(string.format("  【SECTION 5: NEWLY CREATED UMG WIDGETS (Total: %d)】\n", #sec_new_widgets))
    f:write("----------------------------------------------------------------------------------------\n")
    if #sec_new_widgets == 0 then
        f:write("  (None)\n\n")
    else
        for _, l in ipairs(sec_new_widgets) do f:write(l .. "\n\n") end
    end

    -- SECTION 6: TRANSFORM & ROTATION SHIFTS
    f:write("----------------------------------------------------------------------------------------\n")
    f:write(string.format("  【SECTION 6: TRANSFORM & ROTATION SHIFTS (Total: %d)】\n", #sec_transform_changes))
    f:write("----------------------------------------------------------------------------------------\n")
    if #sec_transform_changes == 0 then
        f:write("  (None)\n\n")
    else
        for _, l in ipairs(sec_transform_changes) do f:write(l .. "\n\n") end
    end

    f:write("========================================================================================\n")
    f:write("  END OF REPORT\n")
    f:write("========================================================================================\n")
    f:close()
end

-- -----------------------------------------------------------------------------
-- Script UI
-- -----------------------------------------------------------------------------
local function count_map(m)
    if not m then return 0 end
    local c = 0
    for _ in pairs(m) do c = c + 1 end
    return c
end

local function render_ui()
    imgui.text("======================================================================")
    imgui.text_colored("  OFF-SCREEN TARGET LOCATOR DIFFERENTIAL HUNTER", 0xFF00FFCC)
    imgui.text("======================================================================")
    imgui.text("Hunting for: The screen-center [>] TGT / MQ-99 Arrow Indicator!")
    imgui.separator()

    -- STEP 1: CAPTURE STATE A
    imgui.text_colored("Step 1: Capture Normal / On-Screen State (Arrow NOT Shown)", 0xFFFFAA00)
    if imgui.button("  [1] CAPTURE STATE A (Target ON-SCREEN / No TGT Arrow)  ##btn_snap_a") then
        SnapshotA = capture_current_state("State A (On-Screen)")
    end
    imgui.same_line()
    if SnapshotA then
        imgui.text_colored(string.format("OK! Captured at %s (Actors:%d, Comps:%d, Widgets:%d)",
            SnapshotA.time, count_map(SnapshotA.actors), count_map(SnapshotA.components), count_map(SnapshotA.widgets)), 0xFF88FF88)
    else
        imgui.text_colored("Not captured yet.", 0xFFAAAAAA)
    end

    imgui.separator()

    -- STEP 2: CAPTURE STATE B
    imgui.text_colored("Step 2: Capture Off-Screen State (TGT Arrow IS Shown)", 0xFFFFAA00)
    if imgui.button("  [2] CAPTURE STATE B (Target OFF-SCREEN / TGT Arrow Active)  ##btn_snap_b") then
        SnapshotB = capture_current_state("State B (Off-Screen)")
    end
    imgui.same_line()
    if SnapshotB then
        imgui.text_colored(string.format("OK! Captured at %s (Actors:%d, Comps:%d, Widgets:%d)",
            SnapshotB.time, count_map(SnapshotB.actors), count_map(SnapshotB.components), count_map(SnapshotB.widgets)), 0xFF88FF88)
    else
        imgui.text_colored("Not captured yet.", 0xFFAAAAAA)
    end

    imgui.separator()

    -- STEP 3: COMPARE & GENERATE REPORT
    imgui.text_colored("Step 3: Compare & Generate Diff Report", 0xFFFFAA00)
    local can_compare = (SnapshotA ~= nil and SnapshotB ~= nil)
    if can_compare then
        if imgui.button(">>> [3] COMPARE & GENERATE DIFF REPORT NOW <<<##btn_compare") then
            compare_snapshots_and_write_report()
        end
        imgui.same_line()
        imgui.text_colored("(Writes to " .. REPORT_FILE .. ")", 0xFFAAAAFF)
    else
        imgui.text_colored("Please capture both State A and State B first.", 0xFF888888)
    end

    -- SUMMARY DISPLAY
    if DiffSummary.compared_time then
        imgui.separator()
        imgui.text_colored("=== LATEST DIFF COMPARISON RESULTS ===", 0xFFFFFF00)
        imgui.text(string.format("Compared at: %s", DiffSummary.compared_time))
        imgui.text_colored(string.format("  🎯 'TGT' / Target Text Matches    : %d items", DiffSummary.text_hits), 0xFF00FFFF)
        imgui.text_colored(string.format("  ★ Priority Watchlist Highlights : %d items", DiffSummary.watched_changes), 0xFFFF5555)
        imgui.text(string.format("  * Objects Became Visible         : %d (Actors:%d, Comps:%d, Widgets:%d)",
            DiffSummary.vis_actors + DiffSummary.vis_comps + DiffSummary.vis_widgets,
            DiffSummary.vis_actors, DiffSummary.vis_comps, DiffSummary.vis_widgets))
        imgui.text(string.format("  * Newly Spawned/Created Objects  : %d (Actors:%d, Comps:%d, Widgets:%d)",
            DiffSummary.new_actors + DiffSummary.new_comps + DiffSummary.new_widgets,
            DiffSummary.new_actors, DiffSummary.new_comps, DiffSummary.new_widgets))
        imgui.text_colored(string.format("Report successfully saved to: %s", DiffSummary.report_path or REPORT_FILE), 0xFF88FF88)
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully. Zero-tick scanning.", SCRIPT_NAME))
