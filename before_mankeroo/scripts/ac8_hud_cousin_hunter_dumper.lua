--[[
  ============================================================================
  ac8_hud_cousin_hunter_dumper.lua : HUD "Cousin" & Target Arrow Deep Dumper
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR + OpenXR
  Purpose:    Deep-scan and dump:
                1. Pitch Ladder's "Cousins" (all widgets sharing the same parent canvas/tree)
                2. Target Arrow / Locator / Guide / Pointer / Indicator candidates (UMG & 3D)
                3. Player Pawn full components & targeting state
                4. 3D HUD Actors (LiveMainHUDParent, 3DUI, TargetContainers)
                5. HUD Texture2D catalog (sleeping arrow/guide textures)
              Plus:
                Interactive "Force Visible / Blink / Nudge" test panel to verify
                visual elements live in VR!
  Output:     data/ac8_hud_cousin_dump.txt
  Safety:     100% Pure ASCII, Game-Thread Only, Crash-Safe
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "AC8-COUSIN-HUNTER"
local DUMP_FILE   = "data/ac8_hud_cousin_dump.txt"

-- -----------------------------------------------------------------------------
-- 0. Safe Utilities
-- -----------------------------------------------------------------------------
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
    if not obj then return "nil" end
    local ok, c = pcall(function() return obj:get_class():get_name() end)
    return (ok and type(c) == "string") and c or "unknown"
end

local function get_short_name(obj)
    local fn = get_safe_name(obj)
    return fn:match("([^.]+)$") or fn
end

local vis_names = {
    [0] = "Visible",
    [1] = "Collapsed",
    [2] = "Hidden",
    [3] = "HitTestInvisible",
    [4] = "SelfHitTestInvisible"
}

-- -----------------------------------------------------------------------------
-- 1. Dump File Logging
-- -----------------------------------------------------------------------------
local dump_handle = nil
local function open_dump()
    local ok, f = pcall(function() return io.open(DUMP_FILE, "w") end)
    if ok and f then
        dump_handle = f
        return true
    end
    return false
end

local function dlog(fmt, ...)
    local str = string.format(fmt, ...)
    print(string.format("[%s] %s", SCRIPT_NAME, str))
    if dump_handle then
        pcall(function()
            dump_handle:write(str .. "\n")
            dump_handle:flush()
        end)
    end
end

local function close_dump()
    if dump_handle then
        pcall(function() dump_handle:close() end)
        dump_handle = nil
    end
end

-- -----------------------------------------------------------------------------
-- 2. State & Interactive Test Target
-- -----------------------------------------------------------------------------
local S = {
    dump_status         = "Ready. Press [Run Full Deep Dump] below.",
    dump_timestamp      = "Never",
    
    -- Discovered Candidates for Interactive Test
    candidate_widgets   = {}, -- list of { widget, name, full, class }
    selected_idx        = 1,
    test_force_visible  = false,
    test_scale          = 2.0,
    test_offset_x       = 0.0,
    test_offset_y       = 0.0,
    test_blink          = false,
    blink_state         = false,
}

-- -----------------------------------------------------------------------------
-- 3. Core Dumper Logic
-- -----------------------------------------------------------------------------
local function run_deep_dump()
    if not open_dump() then
        S.dump_status = "ERROR: Failed to open " .. DUMP_FILE
        return
    end

    S.dump_status = "Dumping in progress..."
    local t_now = os.date("%Y-%m-%d %H:%M:%S")

    dlog("====================================================================")
    dlog("  ACE COMBAT 8 : HUD COUSIN & TARGET LOCATOR DEEP INVESTIGATION")
    dlog("  Time: %s", t_now)
    dlog("====================================================================")
    dlog("")

    -- ------------------------------------------------------------------
    -- SECTION 1: Player Pawn & Targeting Telemetry
    -- ------------------------------------------------------------------
    dlog("--------------------------------------------------------------------")
    dlog("【SECTION 1: PLAYER PAWN & TARGETING STATE】")
    dlog("--------------------------------------------------------------------")
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    local target_actor = nil
    if pawn then
        dlog("  Player Pawn: %s", get_safe_name(pawn))
        dlog("  Pawn Class : %s", get_safe_class_name(pawn))
        local p_loc = safe_call(function() return pawn:call("K2_GetActorLocation") end, nil)
        if p_loc then
            dlog("  Pawn Location: X=%.1f, Y=%.1f, Z=%.1f", p_loc.X or p_loc.x or 0, p_loc.Y or p_loc.y or 0, p_loc.Z or p_loc.z or 0)
        end

        -- Targeting components
        local ts_comp = safe_call(function() return pawn.TargetSelection end, nil)
        if ts_comp then
            target_actor = safe_call(function() return ts_comp.SelectedTarget end, nil)
            dlog("  * TargetSelection.SelectedTarget = %s", get_safe_name(target_actor))
        end
        local focus_comp = safe_call(function() return pawn.FocusTargetComponent end, nil)
        if focus_comp then
            local ft = safe_call(function() return focus_comp.FocusTarget end, nil)
            dlog("  * FocusTargetComponent.FocusTarget = %s", get_safe_name(ft))
            if not target_actor then target_actor = ft end
        end

        -- Dump ALL Components on Player Pawn (Full 77+ components)
        local comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
        if comp_class then
            local comps = safe_call(function() return pawn:call("K2_GetComponentsByClass", comp_class) end, {})
            dlog("  Total Components on Pawn: %d", #comps)
            for idx, c in ipairs(comps) do
                local cn = get_safe_class_name(c)
                local sn = get_short_name(c)
                local fn = get_safe_name(c)
                local is_relevant = false
                local lfn = fn:lower()
                if lfn:find("target") or lfn:find("hud") or lfn:find("camera") or lfn:find("weapon") or
                   lfn:find("aim") or lfn:find("mesh") or lfn:find("fcs") or lfn:find("arrow") or lfn:find("radar") then
                    is_relevant = true
                end
                if is_relevant then
                    dlog("    ★ [%02d] %s (Class: %s)", idx, sn, cn)
                    -- Check properties
                    for _, p in ipairs({ "SelectedTarget", "FocusTarget", "CurrentTarget", "LockedTarget", "LockOnRange" }) do
                        pcall(function()
                            local v = c[p]
                            if v ~= nil then dlog("          -> Property '%s' = %s", p, get_safe_name(v)) end
                        end)
                    end
                else
                    dlog("      [%02d] %s (Class: %s)", idx, sn, cn)
                end
            end
        end
    else
        dlog("  [WARN] Player Pawn not found!")
    end
    dlog("")

    -- ------------------------------------------------------------------
    -- SECTION 2: Pitch Ladder's "Cousins" (MainFlight Tree Full Scan)
    -- ------------------------------------------------------------------
    dlog("--------------------------------------------------------------------")
    dlog("【SECTION 2: PITCH LADDER'S COUSINS (MainFlight Canvas Hierarchy)】")
    dlog("--------------------------------------------------------------------")
    dlog("Scanning all widgets sharing the MainFlight / MainCanvas / DynamicDraw tree...")

    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    local all_widgets = {}
    if widget_class then
        all_widgets = safe_call(function() return widget_class:get_objects_matching(false) end, {})
    end
    dlog("  Total UWidgets in Memory: %d", #all_widgets)

    local mainflight_widgets = {}
    local cousin_keywords = {
        "pitch", "ladder", "horizon", "landing", "gun", "reticle", "velocity",
        "whisky", "outer", "end0", "end4", "mad", "marker", "locator", "seeker",
        "target", "waypoint", "canvas", "tachometer", "altimeter", "flight"
    }

    local test_candidates = {}

    for _, w in ipairs(all_widgets) do
        local fn = get_safe_name(w)
        if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
            if fn:find("MainFlight", 1, true) or fn:find("HUD_Chronicle", 1, true) then
                table.insert(mainflight_widgets, w)

                local lfn = fn:lower()
                for _, kw in ipairs(cousin_keywords) do
                    if lfn:find(kw, 1, true) then
                        table.insert(test_candidates, {
                            widget = w,
                            name   = get_short_name(w),
                            full   = fn,
                            class  = get_safe_class_name(w)
                        })
                        break
                    end
                end
            end
        end
    end

    dlog("  MainFlight Widgets Count: %d", #mainflight_widgets)
    dlog("  High-Priority Cousin Candidates: %d\n", #test_candidates)

    for idx, w in ipairs(mainflight_widgets) do
        local fn = get_safe_name(w)
        local cn = get_safe_class_name(w)
        local sn = get_short_name(w)

        local vis_code = safe_call(function() return w:call("GetVisibility") end, -1)
        local vis_str = vis_names[vis_code] or tostring(vis_code)

        local parent_name = "None"
        pcall(function()
            local p = w:call("GetParent")
            if p then parent_name = get_short_name(p) end
        end)

        local sz_w, sz_h = 0, 0
        pcall(function()
            local ds = w:call("GetDesiredSize")
            if ds then sz_w, sz_h = ds.X or 0, ds.Y or 0 end
        end)

        local tx, ty, rot = 0, 0, 0
        pcall(function()
            local rt = w.RenderTransform
            if rt then
                if rt.Translation then tx, ty = rt.Translation.X or 0, rt.Translation.Y or 0 end
                if rt.Angle then rot = rt.Angle end
            end
        end)

        local sx, sy = 1.0, 1.0
        pcall(function()
            local rt = w.RenderTransform
            if rt and rt.Scale then sx, sy = rt.Scale.X or 1.0, rt.Scale.Y or 1.0 end
        end)

        -- Brush / Texture if Image
        local brush_res = ""
        pcall(function()
            local b = w.Brush
            if b and b.ResourceObject then
                brush_res = " | Brush: " .. get_short_name(b.ResourceObject)
            end
        end)

        -- Highlight cousins
        local is_highlight = false
        local lsn = sn:lower()
        for _, kw in ipairs(cousin_keywords) do
            if lsn:find(kw, 1, true) then is_highlight = true; break end
        end

        local prefix = is_highlight and "  ★" or "   "
        dlog("%s [%03d] %-30s | Class: %-22s | Vis: %-18s | Parent: %-20s", prefix, idx, sn, cn, vis_str, parent_name)
        dlog("        Size: (%.1f, %.1f) | RT: (X=%.1f, Y=%.1f, Scale=%.2f,%.2f, Angle=%.1f)%s", sz_w, sz_h, tx, ty, sx, sy, rot, brush_res)
        dlog("        Path: %s", fn)
        dlog("")
    end

    -- ------------------------------------------------------------------
    -- SECTION 3: Dedicated Target Arrow / Locator / Guide Candidates
    -- ------------------------------------------------------------------
    dlog("--------------------------------------------------------------------")
    dlog("【SECTION 3: TARGET ARROW / LOCATOR / GUIDE / POINTER CANDIDATES】")
    dlog("--------------------------------------------------------------------")
    dlog("Searching ALL widgets in memory for arrow/locator/pointer keywords...")

    local arrow_kws = {
        "locator", "arrow", "pointer", "direction", "pin", "guide", "lead",
        "offscreen", "chevron", "triangle", "seeker", "targetselection"
    }

    local matched_arrows = {}
    for _, w in ipairs(all_widgets) do
        local fn = get_safe_name(w)
        if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
            local lfn = fn:lower()
            for _, kw in ipairs(arrow_kws) do
                if lfn:find(kw, 1, true) then
                    table.insert(matched_arrows, w)
                    break
                end
            end
        end
    end

    dlog("  Total Arrow/Locator Matches in Memory: %d\n", #matched_arrows)
    for idx, w in ipairs(matched_arrows) do
        local fn = get_safe_name(w)
        local cn = get_safe_class_name(w)
        local sn = get_short_name(w)
        local vis_code = safe_call(function() return w:call("GetVisibility") end, -1)
        local vis_str = vis_names[vis_code] or tostring(vis_code)
        dlog("  [%02d] %-32s (Class: %s) -> Vis: %s", idx, sn, cn, vis_str)
        dlog("       FullName: %s", fn)
    end
    dlog("")

    -- ------------------------------------------------------------------
    -- SECTION 4: 3D HUD Actors & World Components
    -- ------------------------------------------------------------------
    dlog("--------------------------------------------------------------------")
    dlog("【SECTION 4: 3D HUD ACTORS, MESHES & BILLBOARDS IN WORLD】")
    dlog("--------------------------------------------------------------------")
    local actor_class = api:find_uobject("Class /Script/Engine.Actor")
    if actor_class then
        local all_acts = safe_call(function() return actor_class:get_objects_matching(false) end, {})
        dlog("  Total Actors in World: %d", #all_acts)

        local hud_acts = {}
        for _, a in ipairs(all_acts) do
            local fn = get_safe_name(a)
            if not fn:find("Default__", 1, true) then
                local lfn = fn:lower()
                if lfn:find("hud") or lfn:find("locator") or lfn:find("targetcontainer") or
                   lfn:find("3dui") or lfn:find("aerialrefuel") or lfn:find("arrow") or lfn:find("pointer") then
                    table.insert(hud_acts, a)
                end
            end
        end

        dlog("  HUD / Target 3D Actors Count: %d\n", #hud_acts)
        for idx, a in ipairs(hud_acts) do
            local sn = get_short_name(a)
            local cn = get_safe_class_name(a)
            local fn = get_safe_name(a)
            local loc = safe_call(function() return a:call("K2_GetActorLocation") end, nil)
            local loc_str = loc and string.format("(X=%.0f, Y=%.0f, Z=%.0f)", loc.X or loc.x or 0, loc.Y or loc.y or 0, loc.Z or loc.z or 0) or "nil"
            local bHidden = safe_call(function() return a.bHiddenInGame end, "unknown")

            dlog("  [%02d] Actor: %-35s (Class: %s)", idx, sn, cn)
            dlog("       Location: %s | bHiddenInGame: %s", loc_str, tostring(bHidden))

            -- Dump components of this 3D Actor
            local comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
            if comp_class then
                local comps = safe_call(function() return a:call("K2_GetComponentsByClass", comp_class) end, {})
                for c_idx, c in ipairs(comps) do
                    local c_sn = get_short_name(c)
                    local c_cn = get_safe_class_name(c)
                    local c_vis = safe_call(function() return c.bVisible end, "unknown")
                    dlog("         Comp [%02d]: %-30s | Class: %-25s | Vis: %s", c_idx, c_sn, c_cn, tostring(c_vis))
                end
            end
            dlog("")
        end
    end

    -- ------------------------------------------------------------------
    -- SECTION 5: Sleeping HUD Texture2D Catalog
    -- ------------------------------------------------------------------
    dlog("--------------------------------------------------------------------")
    dlog("【SECTION 5: SLEEPING HUD TEXTURE2D CATALOG】")
    dlog("--------------------------------------------------------------------")
    local tex_class = api:find_uobject("Class /Script/Engine.Texture2D")
    if tex_class then
        local all_tex = safe_call(function() return tex_class:get_objects_matching(false) end, {})
        dlog("  Total Texture2D in Memory: %d", #all_tex)

        local hud_textures = {}
        for _, t in ipairs(all_tex) do
            local fn = get_safe_name(t)
            local lfn = fn:lower()
            if lfn:find("/hud/") or lfn:find("t_hud_") or lfn:find("pitchmeter") or
               lfn:find("target") or lfn:find("arrow") or lfn:find("pointer") or lfn:find("guide") then
                table.insert(hud_textures, t)
            end
        end

        dlog("  HUD / Guide / Target Textures Count: %d\n", #hud_textures)
        for idx, t in ipairs(hud_textures) do
            local sn = get_short_name(t)
            local fn = get_safe_name(t)
            dlog("  [%03d] %-35s -> %s", idx, sn, fn)
        end
    end

    dlog("")
    dlog("====================================================================")
    dlog("  DEEP DUMP COMPLETE. Saved to: %s", DUMP_FILE)
    dlog("====================================================================")

    close_dump()

    S.candidate_widgets = test_candidates
    S.dump_timestamp = t_now
    S.dump_status = string.format("Dump Finished at %s! (%d Cousins, %d MainFlight, %d Textures)",
                                  t_now, #test_candidates, #mainflight_widgets, #matched_arrows)
    print(string.format("[%s] %s", SCRIPT_NAME, S.dump_status))
end

-- -----------------------------------------------------------------------------
-- 4. Interactive Live Blink / Visibility Test Loop
-- -----------------------------------------------------------------------------
local tick_count = 0
uevr.sdk.callbacks.on_post_engine_tick(function()
    tick_count = tick_count + 1

    if not S.test_force_visible and not S.test_blink then return end

    local cand = S.candidate_widgets[S.selected_idx]
    if not cand or not cand.widget then return end

    local w = cand.widget

    -- Blink toggle every 15 ticks (0.25s)
    if S.test_blink then
        if tick_count % 15 == 0 then
            S.blink_state = not S.blink_state
        end
    else
        S.blink_state = true
    end

    pcall(function()
        if S.blink_state then
            w:call("SetVisibility", 0) -- Visible
            w.RenderOpacity = 1.0
            w:SetRenderScale({ X = S.test_scale, Y = S.test_scale })
            w:SetRenderTranslation({ X = S.test_offset_x, Y = S.test_offset_y })
        else
            w:call("SetVisibility", 2) -- Hidden
        end
    end)
end)

-- -----------------------------------------------------------------------------
-- 5. ImGui Control Panel
-- -----------------------------------------------------------------------------
local function render_ui()
    imgui.text("====================================================")
    imgui.text_colored("  AC8 HUD COUSIN & TARGET ARROW HUNTER (DUMPER)", 0xFF00FFCC)
    imgui.text("====================================================")

    imgui.text(string.format("Status: %s", S.dump_status))
    imgui.text(string.format("Last Dumped: %s", S.dump_timestamp))

    if imgui.button(">>> RUN FULL DEEP DUMP NOW <<<##btn_run_dump") then
        run_deep_dump()
    end
    imgui.same_line()
    imgui.text_colored("(Writes to data/ac8_hud_cousin_dump.txt)", 0xFFAAAAFF)

    imgui.separator()

    -- --------------------------------------------------------------------
    -- Interactive Visual Probe Section
    -- --------------------------------------------------------------------
    imgui.text_colored("【Interactive Live Visual Test: Bring Widget to VR!】", 0xFFFFAA00)
    imgui.text("Select a discovered candidate and force it onto screen to see what it is:")

    if #S.candidate_widgets > 0 then
        local current_cand = S.candidate_widgets[S.selected_idx]
        local current_label = current_cand and string.format("[%d] %s (%s)", S.selected_idx, current_cand.name, current_cand.class) or "None"

        if imgui.begin_combo("Candidate Widget##combo_cand", current_label) then
            for idx, c in ipairs(S.candidate_widgets) do
                local is_sel = (idx == S.selected_idx)
                if imgui.selectable(string.format("[%02d] %s (%s)##item_%d", idx, c.name, c.class, idx), is_sel) then
                    S.selected_idx = idx
                end
            end
            imgui.end_combo()
        end

        local ch_vis, val_vis = imgui.checkbox("Force Visible on Screen##chk_vis", S.test_force_visible)
        if ch_vis then S.test_force_visible = val_vis end

        imgui.same_line()
        local ch_blk, val_blk = imgui.checkbox("Blink (Flash) to Locate##chk_blk", S.test_blink)
        if ch_blk then S.test_blink = val_blk end

        local ch_sc, val_sc = imgui.slider_float("Test Scale (Size)##t_sc", S.test_scale, 0.5, 10.0)
        if ch_sc then S.test_scale = val_sc end

        local ch_ox, val_ox = imgui.slider_float("Move X##t_ox", S.test_offset_x, -1000.0, 1000.0)
        if ch_ox then S.test_offset_x = val_ox end

        local ch_oy, val_oy = imgui.slider_float("Move Y##t_oy", S.test_offset_y, -1000.0, 1000.0)
        if ch_oy then S.test_offset_y = val_oy end

        if imgui.button("Center (0,0)##btn_center") then S.test_offset_x = 0; S.test_offset_y = 0 end
        imgui.same_line()
        if imgui.button("Pitch Ladder Position##btn_ladder_pos") then S.test_offset_x = 0; S.test_offset_y = 0 end
    else
        imgui.text_colored("No candidates cached yet. Click [RUN FULL DEEP DUMP] above!", 0xFFFF5555)
    end

    imgui.separator()
    imgui.text("Tip: After dumping, open data/ac8_hud_cousin_dump.txt to view the full hierarchy.")
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] Loaded successfully. Press button in Script UI to dump.", SCRIPT_NAME))
