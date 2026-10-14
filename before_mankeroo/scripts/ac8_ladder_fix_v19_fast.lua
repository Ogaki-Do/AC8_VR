--[[
  AC8 HUD Customizer (v29 - Release Candidate)
  Controls PitchLadder, Heading, Radar, AircraftInfo, Score.
  100% Pure ASCII for UEVR compatibility.
]]

local api = uevr.api
if api == nil then return end

--  
-- UEVR  Reset scripts 
local SCRIPT_VERSION = "v29"

--------------------------------------------------------------------------
-- 
--
--  x / y / op / sc / active 
-- apply  nil ****
-- v2  x/y
--------------------------------------------------------------------------
local TARGETS = {
    {
        key    = "ladder",
        label  = "PitchLadder",
        from   = { "PitchMeter" },
        nodes  = {
            "Altimeter",
            "Velocity",
            "VelocityIcon",
        },
        subnames = { "Velocity", "VelocityIcon" },
        sublabel = "Heading",
        x = 690.0, y = 756.0, active = true, op = 0.95, sc = 1.0,
        sdx = -1913.0, sdy = -1200.0,
        hsc = 1.0,
        wx = 0.0, wy = 0.0, wsc = 1.0,
        cascade = true,
    },
    {
        key    = "radar",
        label  = "Radar",
        from   = { "MiniMap", "Radar" },
        nodes  = {
            "MiniMapLayer",
            "MIniMapCanvas",
            "RadarCircleCanvasPanel",
            "RadarCircleBase",
            "MiniMapIconCanvasPanel",
            "MiniMapCornerCanvas",
            "MiniMapSearchCorners",
            "MiniMapEnlargedCorners",
        },
        x = 0.0, y = 0.0, active = true, op = 0.95, sc = 1.0,
        cascade = true,
    },
    {
        key    = "info",
        label  = "AircraftInfo",
        from   = { "PlayerState", "PlayerStatus" },
        nodes  = {
            "WBP_PlayerStateWidget",
            "PlaneIconStatPanel",
            "PlaneCanvas",
            "PlaneTextStatPanel",
            "PlayerNamePanel",
            "Weapons",
            "WeaponsADMM",
            "Flares",
            "IconsCanvas",
        },
        x = 0.0, y = 0.0, active = true, op = 0.95, sc = 1.0,
        cascade = true,
    },
    {
        key    = "score",
        label  = "Score / MissionInfo",
        from   = { "CampaignInfo", "PrivateScore", "TGT_Box" },
        nodes  = {
            "WBP_HUD_SubWidgets_Parts_CampaignInfo_000_C",
            "VerticalBox_39",
            "CampaignInfo",
            "ForEachWidget",
        },
        x = 0.0, y = 0.0, active = true, op = 0.95, sc = 1.0,
        cascade = true,
    },
    {
        key    = "drawcanvas",
        label  = "Draw canvas",
        from   = { "WorldToScreen", "DynamicDraw", "NoGlow" },
        nodes  = {
            "LowestPriorityDynamicDrawCanvas",
            "LowestPriorityCanvasWorldToScreenDraw",
            "WorldToScreenDrawCanvas",
            "TopPriorityCanvas",
            "MainCanvas",
            "DynamicDrawCanvas",
            "NoGlowDynamicDrawCanvas",
        },
        nopos = true,
        x = 0.0, y = 0.0, active = true, op = 0.95, sc = 1.0,
        cascade = true,
    },
}

-- Scope: Only recognize containers under Flight HUD
local SCOPE = "WBP_HUD_Chronicle_MainFlight_000_C"

-- Defaults snapshot
local DEFAULTS = {}
for _, t in ipairs(TARGETS) do
    DEFAULTS[t.key] = {
        x = t.x, y = t.y, active = t.active, op = t.op or 0.95, sc = t.sc,
        sdx = t.sdx or 0.0, sdy = t.sdy or 0.0,
        hsc = t.hsc or 1.0,
        wx = t.wx or 0.0, wy = t.wy or 0.0, wsc = t.wsc or 1.0,
        cascade = (t.cascade ~= false)
    }
end

-- tick600  10 
--  = 
local RESCAN_EVERY = 1800

local CFG_FILE = "ac8_ladder.json"
local dirty, save_msg = false, ""

--------------------------------------------------------------------------
--  / 
--------------------------------------------------------------------------
local enable_debug_dump = false
local FH = nil

local function log(s)
    if not enable_debug_dump then return end
    if FH == nil then
        local ok, f = pcall(function() return io.open("ac8_ladder_fix.txt", "a") end)
        if ok and f ~= nil then FH = f end
    end
    if FH ~= nil then
        pcall(function() FH:write(tostring(s) .. "\n"); FH:flush() end)
    end
end

--  UFUNCTION  obj.call(obj, "", ...)
local function call(obj, fn, ...)
    local ok, f = pcall(function() return obj[fn] end)
    if ok and f ~= nil then
        local ok2, r = pcall(f, obj, ...)
        if ok2 then return r end
    end
    local ok3, f2 = pcall(function() return obj.call end)
    if ok3 and f2 ~= nil then
        local ok4, r2 = pcall(f2, obj, fn, ...)
        if ok4 then return r2 end
    end
    return nil
end

local function full_name(o)
    local ok, s = pcall(function() return o:get_full_name() end)
    if ok and type(s) == "string" then return s end
    return nil
end

local function leaf(o)
    local s = full_name(o)
    if s ~= nil then return s:match("([^.]+)$") or s end
    return "?"
end

--  "CanvasPanel /Engine/..."
local function path_of(o)
    local s = full_name(o)
    if s == nil then return nil end
    return s:match("^%S+%s+(.*)$") or s
end

-- 
-- Y  LuaVR  tr.Y  nil
-- 
local function num_field(o, names)
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return o[n] end)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

local function get_rt_xy(obj)
    local ok1, rt = pcall(function() return obj:get_property("RenderTransform") end)
    if not ok1 or rt == nil then return nil, nil end
    local ok2, tr = pcall(function() return rt.Translation end)
    if not ok2 or tr == nil then return nil, nil end
    return num_field(tr, { "X", "x" }), num_field(tr, { "Y", "y" })
end

local function get_rt_scale(obj)
    local ok1, rt = pcall(function() return obj:get_property("RenderTransform") end)
    if not ok1 or rt == nil then return nil, nil end
    local ok2, sc = pcall(function() return rt.Scale end)
    if not ok2 or sc == nil then return nil, nil end
    return num_field(sc, { "X", "x" }), num_field(sc, { "Y", "y" })
end

--------------------------------------------------------------------------
-- 
--
-- 
--  /Engine/Transient
-- AltimeterPanel  Altimeter
--------------------------------------------------------------------------
--   CanvasPanel
--    UUserWidget MiniMapLayer  WBP_HUD_Radar_..._C
--    CanvasPanel   
--   
local SEARCH_CLASSES = {}
local UW = nil
do
    for _, path in ipairs({ "Class /Script/UMG.UserWidget",
                            "Class /Script/UMG.CanvasPanel" }) do
        local ok, c = pcall(function() return api:find_uobject(path) end)
        if ok and c ~= nil then
            SEARCH_CLASSES[#SEARCH_CLASSES + 1] = c
            if path:find("UserWidget", 1, true) then UW = c end
        end
    end
end
if #SEARCH_CLASSES == 0 then
    log("!! find_uobject  not found")
end

-- --------------------------------------------------------------------------
-- HUD/
-- --------------------------------------------------------------------------
local ticks = 0
local current_mf = nil
local last_mf_search_tick = -999

local function get_main_flight(force_search)
    -- 1. 
    if current_mf ~= nil then
        local ok, nm = pcall(function() return current_mf:get_full_name() end)
        if ok and type(nm) == "string" and nm:find(SCOPE, 1, true) then
            local okinv, inv = pcall(function() return current_mf:IsInViewport() end)
            if okinv and inv == true then
                local okvis, vis = pcall(function() return current_mf:GetVisibility() end)
                if not okvis or (vis ~= 1 and vis ~= 2) then -- 1=Collapsed, 2=Hidden
                    return current_mf
                end
            end
        end
        current_mf = nil
    end

    -- 2.  15  0.25  Pawn 
    if not force_search and (ticks - last_mf_search_tick < 15) then
        return nil
    end
    last_mf_search_tick = ticks

    if UW == nil then return nil end
    local ok, arr = pcall(function() return UW:get_objects_matching(false) end)
    if not ok or type(arr) ~= "table" then return nil end

    for i = #arr, 1, -1 do
        local w = arr[i]
        local okn, nm = pcall(function() return w:get_full_name() end)
        if okn and type(nm) == "string"
            and nm:find("/Engine/Transient", 1, true)
            and nm:find(SCOPE, 1, true)
            and not nm:find(".WidgetTree", 1, true)
            and not nm:find("Default__", 1, true)
        then
            local okinv, inv = pcall(function() return w:IsInViewport() end)
            if okinv and inv == true then
                local okvis, vis = pcall(function() return w:GetVisibility() end)
                if not okvis or (vis ~= 1 and vis ~= 2) then
                    current_mf = w
                    return current_mf
                end
            end
        end
    end
    return nil
end

local function is_flight_active(force)
    return get_main_flight(force) ~= nil
end

-- CanvasPanel_63
-- 
-- 
local function find_all_by_name(node_names)
    if not is_flight_active() then return {} end
    local out = {}
    local want = {}
    for _, n in ipairs(node_names) do want[n] = true end

    --   
    -- 
    local seen = {}
    for _, cls in ipairs(SEARCH_CLASSES) do
        local ok, arr = pcall(function() return cls:get_objects_matching(false) end)
        if ok and type(arr) == "table" then
            for _, w in ipairs(arr) do
                local okn, nm = pcall(function() return w:get_full_name() end)
                if okn and type(nm) == "string"
                    and nm:find("/Engine/Transient", 1, true)
                    and nm:find(SCOPE, 1, true)      -- 
                then
                    local l = nm:match("([^.]+)$") or ""
                    --  _ WBP_HUD_Command_Wingman_Parts_003_01
                    --  _Parts_003
                    local base = l
                    repeat
                        local prev = base
                        base = base:gsub("_%d+$", "")
                        if base == prev then break end
                    until false
                    if (want[l] or want[base]) and not seen[nm] then
                        seen[nm] = true
                        out[#out + 1] = w
                    end
                end
            end
        end
    end
    return out
end

--  
--   
--    + 
--
--   GetParent()
--   GetParent()  UUserWidget  
--    MiniMapIconCanvasPanel  MiniMapLayer / MIniMapCanvas
--   
--    UMG  Outer  WidgetTree
local function is_under(child_path, parent_path)
    if child_path == nil or parent_path == nil then return false end
    if #parent_path >= #child_path then return false end
    return child_path:sub(1, #parent_path) == parent_path
end

local function prune_nested(list)
    if #list < 2 then return list end
    local paths = {}
    for i, o in ipairs(list) do paths[i] = path_of(o) end

    local keep = {}
    for i, o in ipairs(list) do
        local p, nested = paths[i], false
        if p ~= nil then
            for j = 1, #paths do
                if j ~= i and is_under(p, paths[j]) then nested = true; break end
            end
        end
        if not nested then keep[#keep + 1] = o end
    end
    return keep
end

-- 
local function find_by_walk(from_patterns, node_names)
    if not is_flight_active() or UW == nil then return nil, {} end
    local ok, arr = pcall(function() return UW:get_objects_matching(false) end)
    if not ok or type(arr) ~= "table" then return nil, {} end

    local want_node = {}
    for _, n in ipairs(node_names) do want_node[n] = true end

    for _, w in ipairs(arr) do
        local okn, nm = pcall(function() return w:get_full_name() end)
        if okn and type(nm) == "string"
            and nm:find("/Engine/Transient", 1, true)
            and nm:find(SCOPE, 1, true)
        then
            local hit_from = false
            for _, p in ipairs(from_patterns) do
                if nm:find(p, 1, true) then hit_from = true; break end
            end
            if hit_from then
                local chain, cur = {}, w
                for _ = 1, 12 do
                    cur = call(cur, "GetParent")
                    if cur == nil then break end
                    local l = leaf(cur)
                    chain[#chain + 1] = l
                    if want_node[l] then return cur, chain end
                end
                return nil, chain
            end
        end
    end
    return nil, {}
end

-- 
--  get_full_name() + 
--  CPU  GC
--------------------------------------------------------------------------
-- Hierarchical Widget Tree Discovery & Cascade Opacity
--------------------------------------------------------------------------
local function invalidate_all_opaque()
    for _, t in ipairs(TARGETS) do
        t.opApplied = nil
        t.cascadeApplied = nil
    end
end

local function find_node_by_name(root_node, name)
    if root_node == nil then return nil end
    local base = root_node.name:gsub("_%d+$", "")
    if root_node.name == name or base == name then
        return root_node
    end
    if root_node.children ~= nil then
        for _, ch in ipairs(root_node.children) do
            local found = find_node_by_name(ch, name)
            if found ~= nil then return found end
        end
    end
    return nil
end

local function get_widget_children(w)
    if w == nil then return {} end
    local children = {}
    local seen = {}

    -- 1. If UserWidget: check WidgetTree RootWidget
    local ok_wt, wt = pcall(function() return w.WidgetTree or w:get_property("WidgetTree") end)
    if ok_wt and wt ~= nil then
        local ok_rw, rw = pcall(function() return wt.RootWidget or wt:get_property("RootWidget") end)
        if ok_rw and rw ~= nil and rw ~= w then
            local p = tostring(rw)
            if not seen[p] then seen[p] = true; children[#children + 1] = rw end
        end
    end

    -- 2. Direct RootWidget
    local ok_drw, drw = pcall(function() return w.RootWidget or w:get_property("RootWidget") end)
    if ok_drw and drw ~= nil and drw ~= w then
        local p = tostring(drw)
        if not seen[p] then seen[p] = true; children[#children + 1] = drw end
    end

    -- 3. Content property on ContentWidget (Border, SizeBox, Button)
    local ok_cnt, cnt = pcall(function() return w.Content or w:call("GetContent") end)
    if ok_cnt and cnt ~= nil and cnt ~= w then
        local p = tostring(cnt)
        if not seen[p] then seen[p] = true; children[#children + 1] = cnt end
    end

    -- 4. If PanelWidget: GetChildrenCount & GetChildAt (up to 100 children)
    local count = 0
    local ok_c, res_c = pcall(function() return w:call("GetChildrenCount") end)
    if ok_c and type(res_c) == "number" then count = res_c end
    if count == 0 then
        local ok_c2, res_c2 = pcall(function() return w:GetChildrenCount() end)
        if ok_c2 and type(res_c2) == "number" then count = res_c2 end
    end

    if count > 0 then
        for i = 0, math.min(count - 1, 100) do
            local ch = nil
            local ok_ch, res_ch = pcall(function() return w:call("GetChildAt", i) end)
            if ok_ch and res_ch ~= nil then ch = res_ch end
            if ch == nil then
                local ok_ch2, res_ch2 = pcall(function() return w:GetChildAt(i) end)
                if ok_ch2 and res_ch2 ~= nil then ch = res_ch2 end
            end
            if ch ~= nil and ch ~= w then
                local p = tostring(ch)
                if not seen[p] then seen[p] = true; children[#children + 1] = ch end
            end
        end
    end

    return children
end

local function build_node_tree(w, depth, visited, saved_cfg)
    -- Traverse down 8 layers below root widget
    if w == nil or (depth or 0) > 8 then return nil end
    depth = depth or 0
    visited = visited or {}

    local ok_p, ptr = pcall(function() return tostring(w) end)
    if ok_p and ptr ~= nil then
        if visited[ptr] then return nil end
        visited[ptr] = true
    end

    local l = leaf(w)
    local orig_op = 1.0
    pcall(function() orig_op = w:GetRenderOpacity() end)
    if orig_op == nil then pcall(function() orig_op = w:call("GetRenderOpacity") end) end

    local cfg_for_this = saved_cfg
    local cur_op = (cfg_for_this and type(cfg_for_this.op) == "number") and cfg_for_this.op or 1.0
    local cur_cas = (cfg_for_this and type(cfg_for_this.cascade) == "boolean") and cfg_for_this.cascade or false

    local node = {
        o = w,
        k = path_of(w) or l,
        name = l,
        orig_op = orig_op or 1.0,
        op = cur_op,
        cascade = cur_cas,
        applied_op = nil,
        children = {}
    }

    local ch_objs = get_widget_children(w)
    local ch_cfg_map = (cfg_for_this and type(cfg_for_this.children) == "table") and cfg_for_this.children or nil

    for _, ch_w in ipairs(ch_objs) do
        local ch_name = leaf(ch_w)
        local ch_base = ch_name:gsub("_%d+$", "")
        local ch_saved = nil
        if ch_cfg_map then
            ch_saved = ch_cfg_map[ch_name] or ch_cfg_map[ch_base]
        end
        local ch_node = build_node_tree(ch_w, depth + 1, visited, ch_saved)
        if ch_node ~= nil then
            node.children[#node.children + 1] = ch_node
        end
    end

    return node
end

local function apply_node_opacity(node, inherited_op, force)
    if node == nil then return end

    local effective_op = (inherited_op ~= nil) and inherited_op or (node.op or 1.0)

    if force or node.applied_op ~= effective_op then
        pcall(function() node.o:SetRenderOpacity(effective_op) end)
        pcall(function() node.o:call("SetRenderOpacity", effective_op) end)
        node.applied_op = effective_op
    end

    local child_inherited = (inherited_op ~= nil) and inherited_op or ((node.cascade == true) and effective_op or nil)

    if node.children ~= nil then
        for _, ch in ipairs(node.children) do
            apply_node_opacity(ch, child_inherited, force)
        end
    end
end

local function invalidate_node_applied(node)
    if node == nil then return end
    node.applied_op = nil
    if node.children ~= nil then
        for _, ch in ipairs(node.children) do
            invalidate_node_applied(ch)
        end
    end
end

local function restore_node(node)
    if node == nil then return end
    local def_op = node.orig_op or 1.0
    pcall(function() node.o:SetRenderOpacity(def_op) end)
    pcall(function() node.o:call("SetRenderOpacity", def_op) end)
    node.applied_op = nil
    if node.children ~= nil then
        for _, ch in ipairs(node.children) do
            restore_node(ch)
        end
    end
end

local function get_whisky_mark_obj(t)
    if t.whisky_item ~= nil and t.whisky_item.o ~= nil then
        local ok, valid = pcall(function() return t.whisky_item.o:is_valid() end)
        if ok and valid == true then return t.whisky_item.o end
    end
    if t.items ~= nil then
        for _, e in ipairs(t.items) do
            local found = find_node_by_name(e.node, "WhiskyMarkPanel")
            if found ~= nil and found.o ~= nil then
                t.whisky_item = {
                    o = found.o,
                    k = found.k or "WhiskyMarkPanel",
                    orig_op = found.orig_op or 1.0
                }
                return found.o
            end
        end
    end
    local direct = find_all_by_name({ "WhiskyMarkPanel" })
    if direct ~= nil and #direct > 0 then
        t.whisky_item = {
            o = direct[1],
            k = path_of(direct[1]) or "WhiskyMarkPanel",
            orig_op = 1.0
        }
        return direct[1]
    end
    return nil
end

-- Prepare items and capture initial native opacity + child tree
local function prepare_items(t)
    t.items = nil
    t.whisky_item = nil
    if t.objs == nil then return end

    local out = {}
    local saved_all_ch = t.saved_children_op or {}

    for i, o in ipairs(t.objs) do
        local l = leaf(o)
        local base = l:gsub("_%d+$", "")
        local issub = false
        if t.subnames ~= nil then
            for _, nm in ipairs(t.subnames) do
                if l == nm or base == nm then issub = true; break end
            end
        end
        local orig_op = nil
        pcall(function() orig_op = o:GetRenderOpacity() end)
        if orig_op == nil then pcall(function() orig_op = o:call("GetRenderOpacity") end) end

        local saved_ch = saved_all_ch[l] or saved_all_ch[base] or nil
        local node_tree = build_node_tree(o, 0, {}, saved_ch)

        out[i] = {
            o = o,
            k = path_of(o) or l,
            fn = full_name(o),
            sub = issub,
            orig_op = orig_op or 1.0,
            node = node_tree
        }
    end
    t.items = out

    if t.key == "ladder" then
        get_whisky_mark_obj(t)
    end

    t.opApplied = nil
    t.scApplied = nil
    t.cascadeApplied = nil
end

local function find_node(from_patterns, node_names)
    if not is_flight_active() then return {} end
    local list = find_all_by_name(node_names)
    if #list == 0 and is_flight_active() then
        local w = find_by_walk(from_patterns, node_names)
        list = (w ~= nil) and { w } or {}
    end
    return prune_nested(list)
end

--------------------------------------------------------------------------
-- Snapshot and Restore
--------------------------------------------------------------------------
local ORIG = {}

local function key_of(o)
    return path_of(o) or leaf(o)
end

local function remember(e)
    local r = ORIG[e.k]
    if r == nil then
        local ox, oy = get_rt_xy(e.o)
        local sx, sy = get_rt_scale(e.o)
        ORIG[e.k] = { x = ox, y = oy, sx = sx, sy = sy }
    end
end

-- Full restoration
local function restore(e)
    local r = ORIG[e.k]
    if r == nil then return end
    local o = e.o

    local cx, cy = get_rt_xy(o)
    if type(r.x) == "number" and type(r.y) == "number"
        and not (type(cx) == "number" and math.abs(cx - r.x) < 1
                 and type(cy) == "number" and math.abs(cy - r.y) < 1) then
        pcall(function() o:SetRenderTranslation({ X = r.x, Y = r.y }) end)
    end

    local sx, sy = get_rt_scale(o)
    if type(r.sx) == "number" and type(r.sy) == "number"
        and not (type(sx) == "number" and math.abs(sx - r.sx) < 0.01
                 and type(sy) == "number" and math.abs(sy - r.sy) < 0.01) then
        pcall(function() o:SetRenderScale({ X = r.sx, Y = r.sy }) end)
    end

    local orig_op = e.orig_op or 1.0
    pcall(function() o:SetRenderOpacity(orig_op) end)
    pcall(function() o:call("SetRenderOpacity", orig_op) end)
end

--------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------
local function apply_one(t)
    if not is_flight_active() or t.items == nil or #t.items == 0 then return end

    if not t.active then
        if t.applied then
            for _, e in ipairs(t.items) do
                restore(e)
                if e.node ~= nil then restore_node(e.node) end
            end
            if t.key == "ladder" and t.whisky_item ~= nil and t.whisky_item.o ~= nil then
                pcall(function() t.whisky_item.o:SetRenderTranslation({ X = 0.0, Y = 0.0 }) end)
                pcall(function() t.whisky_item.o:SetRenderScale({ X = 1.0, Y = 1.0 }) end)
            end
            t.applied = false
        end
        t.opApplied = nil
        t.scApplied = nil
        t.cascadeApplied = nil
        return
    end

    local sc_dirty = (type(t.sc) == "number" and t.sc ~= t.scApplied)
    local top_inherited = (t.cascade ~= false) and (t.op or 1.0) or nil
    local op_dirty = (t.op ~= t.opApplied or t.cascade ~= t.cascadeApplied)

    -- Top-level containers: Position, Scale, and Opacity
    for _, e in ipairs(t.items) do
        local o = e.o
        remember(e)

        -- Position
        if not t.nopos then
            local ox, oy = 0.0, 0.0
            if e.sub then ox, oy = t.sdx or 0.0, t.sdy or 0.0 end
            local tx, ty = t.x + ox, t.y + oy

            local cx, cy = get_rt_xy(o)
            if not (type(cx) == "number" and math.abs(cx - tx) < 1
                    and type(cy) == "number" and math.abs(cy - ty) < 1) then
                pcall(function() o:SetRenderTranslation({ X = tx, Y = ty }) end)
            end
        end

        -- Scale (Heading can have individual scale t.hsc)
        local target_scale = t.sc or 1.0
        if e.sub and type(t.hsc) == "number" then
            target_scale = target_scale * t.hsc
        end
        local csx, csy = get_rt_scale(o)
        if not (type(csx) == "number" and math.abs(csx - target_scale) < 0.01
                and type(csy) == "number" and math.abs(csy - target_scale) < 0.01) then
            pcall(function() o:SetRenderScale({ X = target_scale, Y = target_scale }) end)
        end

        -- Opacity cascade to children
        if e.node ~= nil then
            apply_node_opacity(e.node, top_inherited, op_dirty)
        else
            local alpha = top_inherited or (e.orig_op or 1.0)
            if op_dirty or e.applied_op ~= alpha then
                pcall(function() o:SetRenderOpacity(alpha) end)
                pcall(function() o:call("SetRenderOpacity", alpha) end)
                e.applied_op = alpha
            end
        end
    end

    -- Special handling for WhiskyMarkPanel (child of Altimeter)
    -- Deterministic: directly computed from config without depending on pre-reload state
    if t.key == "ladder" then
        local wo = get_whisky_mark_obj(t)
        if wo ~= nil and t.whisky_item ~= nil then
            local target_wx = t.wx or 0.0
            local target_wy = t.wy or 0.0

            local cx, cy = get_rt_xy(wo)
            if not (type(cx) == "number" and math.abs(cx - target_wx) < 1
                    and type(cy) == "number" and math.abs(cy - target_wy) < 1) then
                pcall(function() wo:SetRenderTranslation({ X = target_wx, Y = target_wy }) end)
            end

            local target_wsc = t.wsc or 1.0
            local csx, csy = get_rt_scale(wo)
            if not (type(csx) == "number" and math.abs(csx - target_wsc) < 0.01
                    and type(csy) == "number" and math.abs(csy - target_wsc) < 0.01) then
                pcall(function() wo:SetRenderScale({ X = target_wsc, Y = target_wsc }) end)
            end
        end
    end

    if op_dirty then
        t.opApplied = t.op
        t.cascadeApplied = t.cascade
    end
    if sc_dirty then t.scApplied = t.sc end
    t.applied = true
end

local function apply()
    if not is_flight_active() then return end
    for _, t in ipairs(TARGETS) do
        local ok, err = pcall(apply_one, t)
        if not ok then
            log(string.format("!! [%s] apply : %s", t.label, tostring(err)))
        end
    end
end

--------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------
local HAS_JSON = false
pcall(function() HAS_JSON = (json ~= nil and json.dump_file ~= nil) end)

local function cfg_by_key(k)
    for _, t in ipairs(TARGETS) do
        if t.key == k then return t end
    end
    return nil
end

local function serialize_node(node)
    if node == nil then return nil end
    local res = {
        op = node.op or 1.0,
        cascade = (node.cascade ~= false),
    }
    if node.children ~= nil and #node.children > 0 then
        res.children = {}
        for _, ch in ipairs(node.children) do
            res.children[ch.name] = serialize_node(ch)
        end
    end
    return res
end

local function serialize_target_children(t)
    if t.items == nil then return nil end
    local map = {}
    local has_any = false
    for _, e in ipairs(t.items) do
        if e.node ~= nil then
            map[e.node.name] = serialize_node(e.node)
            has_any = true
        end
    end
    return has_any and map or nil
end

local function save_cfg()
    if not HAS_JSON then return false, "no json api" end
    local out = {}
    for _, t in ipairs(TARGETS) do
        out[t.key] = {
            x = t.x, y = t.y, active = t.active, op = t.op or 1.0, sc = t.sc,
            sdx = t.sdx or 0.0, sdy = t.sdy or 0.0,
            hsc = t.hsc or 1.0,
            wx = t.wx or 0.0, wy = t.wy or 0.0, wsc = t.wsc or 1.0,
            cascade = (t.cascade ~= false),
            children_op = serialize_target_children(t),
        }
    end
    local ok = pcall(function() json.dump_file(CFG_FILE, out, 4) end)
    return ok, ok and "saved" or "save FAILED"
end

local function apply_node_saved_cfg(node, saved)
    if node == nil or saved == nil then return end
    if type(saved.op) == "number" then node.op = saved.op end
    if type(saved.cascade) == "boolean" then node.cascade = saved.cascade end
    if type(saved.children) == "table" and node.children ~= nil then
        for _, ch in ipairs(node.children) do
            local ch_saved = saved.children[ch.name] or saved.children[ch.name:gsub("_%d+$", "")]
            if ch_saved ~= nil then
                apply_node_saved_cfg(ch, ch_saved)
            end
        end
    end
    node.applied_op = nil
end

local function apply_cfg_entry(tg, v)
    if type(v) ~= "table" then return false end
    if type(v.x) == "number" then tg.x = v.x end
    if type(v.y) == "number" then tg.y = v.y end
    if type(v.active) == "boolean" then tg.active = v.active end
    if type(v.op) == "number" then tg.op = v.op end
    if type(v.sc) == "number" then tg.sc = v.sc end
    if type(v.sdx) == "number" then tg.sdx = v.sdx end
    if type(v.sdy) == "number" then tg.sdy = v.sdy end
    if type(v.hsc) == "number" then tg.hsc = v.hsc end
    if type(v.wx) == "number" then tg.wx = v.wx end
    if type(v.wy) == "number" then tg.wy = v.wy end
    if type(v.wsc) == "number" then tg.wsc = v.wsc end
    if type(v.cascade) == "boolean" then
        tg.cascade = v.cascade
    elseif type(v.opaque) == "boolean" then
        tg.cascade = v.opaque
    end

    if type(v.children_op) == "table" then
        tg.saved_children_op = v.children_op
        if tg.items ~= nil then
            for _, e in ipairs(tg.items) do
                if e.node ~= nil then
                    local ch_saved = v.children_op[e.node.name]
                    if ch_saved ~= nil then
                        apply_node_saved_cfg(e.node, ch_saved)
                    end
                end
            end
        end
    end

    tg.opApplied = nil
    tg.scApplied = nil
    tg.cascadeApplied = nil
    return true
end

local function read_cfg()
    if not HAS_JSON then return nil end
    local ok, t = pcall(function() return json.load_file(CFG_FILE) end)
    if not ok or type(t) ~= "table" then return nil end
    return t
end

local function load_cfg()
    local t = read_cfg()
    if t == nil then return false end
    local n = 0
    for k, v in pairs(t) do
        local tg = cfg_by_key(k)
        if tg ~= nil and apply_cfg_entry(tg, v) then
            n = n + 1
        end
    end
    return n > 0
end

--  save 
local function load_cfg_one(tg)
    local all = read_cfg()
    if all == nil then return false end
    local v = all[tg.key]
    if v == nil then return false end
    return apply_cfg_entry(tg, v)
end

local function resolve_all(verbose)
    if not is_flight_active() then
        for _, t in ipairs(TARGETS) do
            t.objs, t.items = nil, nil
            t.applied = false
        end
        return
    end
    for _, t in ipairs(TARGETS) do
        if t.objs == nil or #t.objs == 0 or verbose then
            t.objs = find_node(t.from, t.nodes)
            prepare_items(t)
            if verbose then
                if #t.objs > 0 then
                    log(string.format("  [%s]  %d ", t.label, #t.objs))
                    for i, o in ipairs(t.objs) do
                        log(string.format("      %d) %s", i, leaf(o)))
                    end
                else
                    log(string.format("  [%s] !! ", t.label))
                end
            end
        end
    end
end

--  
-- 
local function rescan_all()
    local changed = {}
    for _, t in ipairs(TARGETS) do
        local before = t.items and t.items[1] and t.items[1].k or nil
        t.objs = find_node(t.from, t.nodes)
        prepare_items(t)
        local after = t.items and t.items[1] and t.items[1].k or nil
        if after ~= before then
            changed[#changed + 1] = string.format("%s(%d)", t.label,
                t.objs ~= nil and #t.objs or 0)
        end
    end
    if #changed > 0 then
        log(": " .. table.concat(changed, "  "))
    end
end

-- v19-fast RESCAN_EVERY 
--  10  5  UObject= ""
--  1/55  5  30 rescan_all 
-- Reload targets 
local rescan_idx = 1
local function rescan_one()
    local n = #TARGETS
    if n == 0 then return end
    local t = TARGETS[rescan_idx]
    rescan_idx = rescan_idx % n + 1
    if t.objs ~= nil and #t.objs > 0 and t.items ~= nil and #t.items > 0 then
        local first_obj = t.objs[1]
        local ok, valid = pcall(function() return first_obj:is_valid() end)
        if ok and valid == true then return end
    end
    local before = t.items and t.items[1] and t.items[1].k or nil
    t.objs = find_node(t.from, t.nodes)
    prepare_items(t)
    local after = t.items and t.items[1] and t.items[1].k or nil
    if after ~= before then
        log(string.format(": %s(%d)", t.label,
            t.objs ~= nil and #t.objs or 0))
    end
end

-- --------------------------------------------------------------------------
--  HUD 
-- --------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Emergency UI: Force Show ALL HUD Elements (Instant Cycle)
--------------------------------------------------------------------------
local trigger_instant_cycle = false
local cycle_frame = 0

local function find_mainflight_widgets()
    local umg_class = api:find_uobject("Class /Script/UMG.Widget")
    if not umg_class then return {} end
    local ok, objs = pcall(function() return umg_class:get_objects_matching(false) end)
    if not ok or type(objs) ~= "table" then return {} end
    local out = {}
    for _, w in ipairs(objs) do
        local ok_fn, fn = pcall(function() return w:get_full_name() end)
        if ok_fn and type(fn) == "string" and fn:find("/Engine/Transient", 1, true) and fn:find(SCOPE, 1, true) then
            out[#out + 1] = w
        end
    end
    return out
end

local function set_hud_visibility_all(hide)
    local widgets = find_mainflight_widgets()
    local vis_code = hide and 1 or 4 -- 1 = Collapsed, 4 = SelfHitTestInvisible
    for _, w in ipairs(widgets) do
        pcall(function() w:call("SetVisibility", vis_code) end)
        pcall(function() w:SetVisibility(vis_code) end)
    end
end

local function smart_restore_hud()
    log("==================================================================")
    log("[SMART-RECOVERY] 'Restore Missing HUD'  - ")
    log("==================================================================")

    local actions = {}

    -- 1. Pawn 
    local pawn = api:get_player_pawn()
    if not pawn then pawn = api:get_local_pawn(0) end
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    local pawn_nm = ""
    if pawn then
        pcall(function() pawn_nm = pawn:get_full_name() end)
    end
    if not pawn or (type(pawn_nm) == "string" and pawn_nm:find("DefaultPawn", 1, true)) then
        local msg = "Aircraft Pawn not ready (Menu / Loading)"
        log("[SMART-RECOVERY] !! " .. msg .. " (Pawn=" .. tostring(pawn_nm) .. ")")
        return false, msg
    end
    log("[SMART-RECOVERY] [Pawn OK] " .. tostring(pawn_nm))

    -- 2. UserWidget 
    if UW == nil then
        pcall(function() UW = api:find_uobject("Class /Script/UMG.UserWidget") end)
    end
    if UW == nil then
        return false, "UserWidget class not found"
    end

    local ok, arr = pcall(function() return UW:get_objects_matching(false) end)
    if not ok or type(arr) ~= "table" then
        return false, "Failed to query UMG widgets"
    end

    -- 3. MainFlight 
    local candidate_mf = nil
    for _, w in ipairs(arr) do
        local okn, nm = pcall(function() return w:get_full_name() end)
        if okn and type(nm) == "string"
            and nm:find("/Engine/Transient", 1, true)
            and nm:find(SCOPE, 1, true)
            and not nm:find(".WidgetTree", 1, true)
            and not nm:find("Default__", 1, true)
        then
            candidate_mf = w
            break
        end
    end

    if candidate_mf == nil then
        log("[SMART-RECOVERY] !!  MainFlight ")
        return false, "MainFlight not found in memory"
    end

    current_mf = candidate_mf

    -- A: Viewport 
    local inv = false
    local oki, res_inv = pcall(function() return candidate_mf:IsInViewport() end)
    if oki and res_inv == true then inv = true end

    if not inv then
        local oka = pcall(function() candidate_mf:AddToViewport(0) end)
        if oka then
            table.insert(actions, "Attached Viewport")
            log("[SMART-RECOVERY] [A ] Viewport -> AddToViewport(0) ")
        end
    else
        log("[SMART-RECOVERY] [A OK] MainFlight  Viewport ")
    end

    -- B: Visibility (Collapsed) 
    local vis = -1
    local okv, res_vis = pcall(function() return candidate_mf:GetVisibility() end)
    if okv then vis = res_vis end

    if vis ~= 0 and vis ~= 3 and vis ~= 4 then -- 0=Visible, 3=HitTestInvisible, 4=SelfHitTestInvisible
        pcall(function() candidate_mf:SetVisibility(0) end) -- Visible
        table.insert(actions, "Visibility->Visible")
        log(string.format("[SMART-RECOVERY] [B ] Visibility(%s) -> Visible(0) ", tostring(vis)))
    else
        log("[SMART-RECOVERY] [B OK] MainFlight  Visibility  (" .. tostring(vis) .. ")")
    end

    -- C: Opacity () 
    local op = 1.0
    local oko, res_op = pcall(function() return candidate_mf:GetRenderOpacity() end)
    if oko and type(res_op) == "number" then op = res_op end

    if op < 0.1 then
        pcall(function() candidate_mf:SetRenderOpacity(1.0) end)
        table.insert(actions, "Opacity->1.0")
        log(string.format("[SMART-RECOVERY] [C ] (%.2f) -> 1.0 ", op))
    end

    -- 4.  (DynamicDrawCanvas / LowestPriority ) 
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if widget_class then
        local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
        local canvas_fixed = 0
        for _, w in ipairs(all_w) do
            local fn = safe_call(function() return w:get_full_name() end, "")
            if fn:find("/Engine/Transient", 1, true) and not fn:find("Default__", 1, true) then
                if fn:find("DynamicDrawCanvas", 1, true) or fn:find("LowestPriority", 1, true) then
                    local w_op = safe_call(function() return w:call("GetRenderOpacity") end, 1.0)
                    local w_vis = safe_call(function() return w:call("GetVisibility") end, 0)
                    if (type(w_op) == "number" and w_op < 0.1) or w_vis == 1 or w_vis == 2 then
                        pcall(function() w:call("SetRenderOpacity", 1.0) end)
                        pcall(function() w:call("SetVisibility", 4) end) -- SelfHitTestInvisible
                        canvas_fixed = canvas_fixed + 1
                    end
                end
            end
        end
        if canvas_fixed > 0 then
            table.insert(actions, string.format("Restored %d Canvases", canvas_fixed))
            log(string.format("[SMART-RECOVERY] [C ] %d /", canvas_fixed))
        end
    end

    -- D: 
    for _, t in ipairs(TARGETS) do
        t.objs, t.items = nil, nil
        t.applied = false
        t.opApplied, t.scApplied = nil, nil
    end
    resolve_all(true)
    apply()
    table.insert(actions, "Offsets Applied")
    log("[SMART-RECOVERY] [D ] ")

    local summary_str = (#actions > 0) and table.concat(actions, " + ") or "All states were already normal"
    log("[SMART-RECOVERY] : " .. summary_str)
    return true, summary_str
end

--------------------------------------------------------------------------
--  ASCII
--------------------------------------------------------------------------
local HAS_BUTTON = false
pcall(function() HAS_BUTTON = (imgui ~= nil and imgui.button ~= nil) end)

-- same_line 
local HAS_SAME_LINE = false
pcall(function() HAS_SAME_LINE = (imgui ~= nil and imgui.same_line ~= nil) end)

-- Helper to begin a native UEVR ImGui tree node
-- default_open: boolean
-- ImGuiCond_Once = 2: sets open state only the very first time
local function begin_tree(label, default_open)
    if imgui.set_next_item_open ~= nil then
        pcall(function() imgui.set_next_item_open(default_open == true, 2) end)
    end
    if imgui.tree_node ~= nil then
        local ok, is_open = pcall(function() return imgui.tree_node(label) end)
        if ok then return is_open end
    end
    -- Fallback to collapsing_header
    if imgui.collapsing_header ~= nil then
        local ok, is_open = pcall(function() return imgui.collapsing_header(label) end)
        if ok then return is_open end
    end
    return true
end

local function end_tree()
    if imgui.tree_pop ~= nil then
        pcall(function() imgui.tree_pop() end)
    end
end

-- Helper for position sliders: [-] [ Slider ] [+] Label: val
local function render_stepped_slider(label, val, min_v, max_v, step, id)
    local changed = false
    local cur = val or 0.0

    if imgui.button(" - ##dec_" .. id) then
        cur = cur - step
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    local cs, vs = imgui.slider_float("##s_" .. id, cur, min_v, max_v)
    if cs then
        cur = vs
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    if imgui.button(" + ##inc_" .. id) then
        cur = cur + step
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    imgui.text(" " .. label .. string.format(": %.1f", cur))

    if changed and enable_debug_dump then
        log(string.format("[SLIDER] %s = %.1f", label, cur))
    end

    return changed, cur
end

-- Helper for opacity slider: [-] [ Slider ] [+] Label: val
local function render_stepped_slider_opacity(label, val, min_v, max_v, step, id)
    local changed = false
    local cur = val or 1.0

    if imgui.button(" - ##dec_" .. id) then
        cur = math.max(min_v, cur - step)
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    local cs, vs = imgui.slider_float("##s_" .. id, cur, min_v, max_v)
    if cs then
        cur = vs
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    if imgui.button(" + ##inc_" .. id) then
        cur = math.min(max_v, cur + step)
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    imgui.text(" " .. label .. string.format(": %.2f", cur))

    if changed and enable_debug_dump then
        log(string.format("[OPACITY] %s = %.2f", label, cur))
    end

    return changed, cur
end

-- Helper for scale slider: [-] [ Slider ] [+] Label: val (Shows offset from 1.0 so 0.00 = normal 100%)
local function render_stepped_slider_scale(label, val, min_v, max_v, step, id)
    local changed = false
    local cur_mult = val or 1.0
    local cur_disp = cur_mult - 1.0

    if imgui.button(" - ##dec_" .. id) then
        cur_disp = math.max(min_v - 1.0, cur_disp - step)
        cur_mult = cur_disp + 1.0
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    local cs, vs = imgui.slider_float("##s_" .. id, cur_disp, min_v - 1.0, max_v - 1.0)
    if cs then
        cur_disp = vs
        cur_mult = cur_disp + 1.0
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    if imgui.button(" + ##inc_" .. id) then
        cur_disp = math.min(max_v - 1.0, cur_disp + step)
        cur_mult = cur_disp + 1.0
        changed = true
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    imgui.text(" " .. label .. string.format(": %+.2f (x%.2f)", cur_disp, cur_mult))

    if changed and enable_debug_dump then
        log(string.format("[SCALE] %s = %+.2f (mult=%.3f)", label, cur_disp, cur_mult))
    end

    return changed, cur_mult
end

-- Helper for visibility tag
local function get_vtag(t)
    local vtag = ""
    if t.objs ~= nil and t.objs[1] ~= nil then
        local okv, vv = pcall(function() return t.objs[1]:GetVisibility() end)
        if okv and type(vv) == "number" then
            if vv == 1 then vtag = "  [HIDDEN]"
            elseif vv == 2 then vtag = "  [HIDDEN vis=2]"
            else vtag = "  [vis=" .. vv .. "]" end
        end
    end
    return vtag
end

local function render_node_ui(node, id_path, parent_inherited_op, t)
    if node == nil then return end

    local has_children = (node.children ~= nil and #node.children > 0)

    if parent_inherited_op ~= nil then
        -- Inheriting from an ancestor who has Apply to all children Opacity = true
        imgui.text(string.format("   Opacity: %.2f  [Inherited - Uncheck 'Apply to all children Opacity' above to edit]##inh_%s", parent_inherited_op, id_path))
    else
        -- Unlocked! User can adjust this node directly
        if has_children then
            local c_cas, v_cas = imgui.checkbox("Apply to all children Opacity##cas_" .. id_path, node.cascade == true)
            if c_cas then
                node.cascade = v_cas
                dirty = true
                invalidate_node_applied(node)
                if t ~= nil then t.opApplied = nil end
            end
        end

        local c_op, v_op = render_stepped_slider_opacity("Opacity", node.op or 1.0, 0.0, 1.0, 0.05, id_path .. "_op")
        if c_op then
            node.op = v_op
            dirty = true
            invalidate_node_applied(node)
            if t ~= nil then t.opApplied = nil end
        end
    end

    if has_children then
        local child_title = string.format("Child Opacity (%d items)##tree_ch_%s", #node.children, id_path)
        if begin_tree(child_title, false) then
            local child_inherited = (parent_inherited_op ~= nil) and parent_inherited_op or ((node.cascade == true) and (node.op or 1.0) or nil)
            for i, ch in ipairs(node.children) do
                local ch_id = id_path .. "_" .. i
                local ch_title = ch.name .. "##node_" .. ch_id
                if begin_tree(ch_title, false) then
                    render_node_ui(ch, ch_id, child_inherited, t)
                    end_tree()
                end
            end
            end_tree()
        end
    end
end

local function render_target_opacity_ui(t, id)
    if t == nil then return end

    local c_cas, v_cas = imgui.checkbox("Apply to all children Opacity##cas_" .. id, t.cascade ~= false)
    if c_cas then
        t.cascade = v_cas
        t.active = true
        dirty = true
        t.opApplied = nil
        t.cascadeApplied = nil
        if t.items ~= nil then
            for _, e in ipairs(t.items) do
                invalidate_node_applied(e.node)
            end
        end
    end

    local c_op, v_op = render_stepped_slider_opacity("Opacity", t.op or 1.0, 0.0, 1.0, 0.05, id .. "_op")
    if c_op then
        t.op = v_op
        t.active = true
        dirty = true
        t.opApplied = nil
        if t.items ~= nil then
            for _, e in ipairs(t.items) do
                invalidate_node_applied(e.node)
            end
        end
    end


end

local function render_target_child_tree(t, id)
    if t == nil or t.items == nil or #t.items == 0 then return end
    local child_label = string.format("Child Opacity (%d items)##tree_ch_top_%s", #t.items, id)
    if begin_tree(child_label, false) then
        local top_inherited = (t.cascade ~= false) and (t.op or 1.0) or nil
        for i, e in ipairs(t.items) do
            local item_id = id .. "_it_" .. i
            local item_name = (e.node and e.node.name) or ("Item_" .. i)
            local item_title = item_name .. "##node_top_" .. item_id
            if begin_tree(item_title, false) then
                if e.node ~= nil then
                    render_node_ui(e.node, item_id, top_inherited, t)
                else
                    imgui.text("No child components found")
                end
                end_tree()
            end
        end
        end_tree()
    end
end

local function ui_body()
    -- Two horizontal separator lines before title
    if imgui.separator ~= nil then
        imgui.separator()
        imgui.separator()
    else
        imgui.text("----------------------------------------------------------------")
        imgui.text("----------------------------------------------------------------")
    end
    imgui.text("AC8 HUD tune   " .. SCRIPT_VERSION)

    ----------------------------------------------------------------------
    -- 1. PITCHLADDER (Native tree node, default open)
    ----------------------------------------------------------------------
    local t_ladder = cfg_by_key("ladder")
    if t_ladder ~= nil then
        local vtag = get_vtag(t_ladder)
        local ladder_title = "PitchLadder" .. vtag
            .. (t_ladder.active and "   [modified]" or "")
            .. ((t_ladder.objs and #t_ladder.objs > 0) and "" or "   (not found)")
            .. "##tree_ladder"
        if begin_tree(ladder_title, true) then
            if t_ladder.objs ~= nil and #t_ladder.objs > 0 then
                -- 1. Geometry: Scale, X, Y
                local c_sc, v_sc = render_stepped_slider_scale("Scale", t_ladder.sc or 1.0, 0.1, 4.0, 0.05, "ladder_sc")
                if c_sc then
                    t_ladder.sc = v_sc
                    t_ladder.active = true
                    dirty = true
                end

                local def_x = DEFAULTS["ladder"].x or 690.0
                local cur_disp_x = t_ladder.x - def_x
                local cx, vx = render_stepped_slider("PitchLadder X", cur_disp_x, -2500.0, 2500.0, 1.0, "ladder_x")
                if cx then
                    t_ladder.x = def_x + vx
                    t_ladder.active = true
                    dirty = true
                end

                local def_y = DEFAULTS["ladder"].y or 756.0
                local cur_disp_y = def_y - t_ladder.y
                local cy, vy = render_stepped_slider("PitchLadder Y (Up+ / Dn-)", cur_disp_y, -2500.0, 2500.0, 1.0, "ladder_y")
                if cy then
                    t_ladder.y = def_y - vy
                    t_ladder.active = true
                    dirty = true
                end

                -- SUB-NODE: PichHeading (PitchLadder Child, default closed)
                if begin_tree("PichHeading (PitchLadder Child)##tree_heading", false) then
                    local c_hsc, v_hsc = render_stepped_slider_scale("Heading Scale", t_ladder.hsc or 1.0, 0.1, 4.0, 0.05, "heading_sc")
                    if c_hsc then
                        t_ladder.hsc = v_hsc
                        t_ladder.active = true
                        dirty = true
                    end

                    local def_sdx = DEFAULTS["ladder"].sdx or -1913.0
                    local cur_disp_sdx = (t_ladder.sdx or 0.0) - def_sdx
                    local chx, vhx = render_stepped_slider("Heading X", cur_disp_sdx, -2500.0, 2500.0, 1.0, "heading_x")
                    if chx then
                        t_ladder.sdx = def_sdx + vhx
                        t_ladder.active = true
                        dirty = true
                    end

                    local def_sdy = DEFAULTS["ladder"].sdy or -1200.0
                    local cur_disp_sdy = def_sdy - (t_ladder.sdy or 0.0)
                    local chy, vhy = render_stepped_slider("Heading Y (Up+ / Dn-)", cur_disp_sdy, -2500.0, 2500.0, 1.0, "heading_y")
                    if chy then
                        t_ladder.sdy = def_sdy - vhy
                        t_ladder.active = true
                        dirty = true
                    end
                    end_tree()
                end

                -- SUB-NODE: WhiskyMarkPanel (PitchLadder Child, default closed)
                if begin_tree("WhiskyMarkPanel (PitchLadder Child)##tree_whisky", false) then
                    local c_wsc, v_wsc = render_stepped_slider_scale("WhiskyMark Scale", t_ladder.wsc or 1.0, 0.1, 4.0, 0.05, "whisky_sc")
                    if c_wsc then
                        t_ladder.wsc = v_wsc
                        t_ladder.active = true
                        dirty = true
                    end

                    local cur_disp_wx = t_ladder.wx or 0.0
                    local cwx, vwx = render_stepped_slider("WhiskyMark X", cur_disp_wx, -2500.0, 2500.0, 1.0, "whisky_x")
                    if cwx then
                        t_ladder.wx = vwx
                        t_ladder.active = true
                        dirty = true
                    end

                    local cur_disp_wy = -(t_ladder.wy or 0.0)
                    local cwy, vwy = render_stepped_slider("WhiskyMark Y (Up+ / Dn-)", cur_disp_wy, -2500.0, 2500.0, 1.0, "whisky_y")
                    if cwy then
                        t_ladder.wy = -vwy
                        t_ladder.active = true
                        dirty = true
                    end
                    end_tree()
                end

                -- 2. Opacity controls (below XY, above Child)
                render_target_opacity_ui(t_ladder, "ladder")

                -- 3. Child Opacity tree
                render_target_child_tree(t_ladder, "ladder")
            end
            end_tree()
        end
    end

    ----------------------------------------------------------------------
    -- 2. RADAR (Native tree node, default open)
    ----------------------------------------------------------------------
    local t_radar = cfg_by_key("radar")
    if t_radar ~= nil then
        local vtag = get_vtag(t_radar)
        local radar_title = "Radar" .. vtag
            .. (t_radar.active and "   [modified]" or "")
            .. ((t_radar.objs and #t_radar.objs > 0) and "" or "   (not found)")
            .. "##tree_radar"
        if begin_tree(radar_title, true) then
            if t_radar.objs ~= nil and #t_radar.objs > 0 then
                -- 1. Geometry: Scale, X, Y
                local c_sc, v_sc = render_stepped_slider_scale("Scale", t_radar.sc or 1.0, 0.1, 4.0, 0.05, "radar_sc")
                if c_sc then
                    t_radar.sc = v_sc
                    t_radar.active = true
                    dirty = true
                end

                local def_x = DEFAULTS["radar"].x or 0.0
                local cur_disp_x = t_radar.x - def_x
                local cx, vx = render_stepped_slider("Radar X", cur_disp_x, -2500.0, 2500.0, 1.0, "radar_x")
                if cx then
                    t_radar.x = def_x + vx
                    t_radar.active = true
                    dirty = true
                end

                local def_y = DEFAULTS["radar"].y or 0.0
                local cur_disp_y = def_y - t_radar.y
                local cy, vy = render_stepped_slider("Radar Y (Up+ / Dn-)", cur_disp_y, -2500.0, 2500.0, 1.0, "radar_y")
                if cy then
                    t_radar.y = def_y - vy
                    t_radar.active = true
                    dirty = true
                end

                -- 2. Opacity controls (below XY, above Child)
                render_target_opacity_ui(t_radar, "radar")

                -- 3. Child Opacity tree
                render_target_child_tree(t_radar, "radar")
            end
            end_tree()
        end
    end

    ----------------------------------------------------------------------
    -- 3. AIRCRAFTINFO (Native tree node, default open)
    ----------------------------------------------------------------------
    local t_info = cfg_by_key("info")
    if t_info ~= nil then
        local vtag = get_vtag(t_info)
        local info_title = "AircraftInfo" .. vtag
            .. (t_info.active and "   [modified]" or "")
            .. ((t_info.objs and #t_info.objs > 0) and "" or "   (not found)")
            .. "##tree_info"
        if begin_tree(info_title, true) then
            if t_info.objs ~= nil and #t_info.objs > 0 then
                -- 1. Geometry: Scale, X, Y
                local c_sc, v_sc = render_stepped_slider_scale("Scale", t_info.sc or 1.0, 0.1, 4.0, 0.05, "info_sc")
                if c_sc then
                    t_info.sc = v_sc
                    t_info.active = true
                    dirty = true
                end

                local def_x = DEFAULTS["info"].x or 0.0
                local cur_disp_x = t_info.x - def_x
                local cx, vx = render_stepped_slider("AircraftInfo X", cur_disp_x, -2500.0, 2500.0, 1.0, "info_x")
                if cx then
                    t_info.x = def_x + vx
                    t_info.active = true
                    dirty = true
                end

                local def_y = DEFAULTS["info"].y or 0.0
                local cur_disp_y = def_y - t_info.y
                local cy, vy = render_stepped_slider("AircraftInfo Y (Up+ / Dn-)", cur_disp_y, -2500.0, 2500.0, 1.0, "info_y")
                if cy then
                    t_info.y = def_y - vy
                    t_info.active = true
                    dirty = true
                end

                -- 2. Opacity controls (below XY, above Child)
                render_target_opacity_ui(t_info, "info")

                -- 3. Child Opacity tree
                render_target_child_tree(t_info, "info")
            end
            end_tree()
        end
    end

    ----------------------------------------------------------------------
    -- 4. SCORE / MISSIONINFO (Native tree node, default open)
    ----------------------------------------------------------------------
    local t_score = cfg_by_key("score")
    if t_score ~= nil then
        local vtag = get_vtag(t_score)
        local score_title = "Score / MissionInfo" .. vtag
            .. (t_score.active and "   [modified]" or "")
            .. ((t_score.objs and #t_score.objs > 0) and "" or "   (not found)")
            .. "##tree_score"
        if begin_tree(score_title, true) then
            if t_score.objs ~= nil and #t_score.objs > 0 then
                -- 1. Geometry: Scale, X, Y
                local c_sc, v_sc = render_stepped_slider_scale("Scale", t_score.sc or 1.0, 0.1, 4.0, 0.05, "score_sc")
                if c_sc then
                    t_score.sc = v_sc
                    t_score.active = true
                    dirty = true
                end

                local def_x = DEFAULTS["score"].x or 0.0
                local cur_disp_x = t_score.x - def_x
                local cx, vx = render_stepped_slider("Score X", cur_disp_x, -2500.0, 2500.0, 1.0, "score_x")
                if cx then
                    t_score.x = def_x + vx
                    t_score.active = true
                    dirty = true
                end

                local def_y = DEFAULTS["score"].y or 0.0
                local cur_disp_y = def_y - t_score.y
                local cy, vy = render_stepped_slider("Score Y (Up+ / Dn-)", cur_disp_y, -2500.0, 2500.0, 1.0, "score_y")
                if cy then
                    t_score.y = def_y - vy
                    t_score.active = true
                    dirty = true
                end

                -- 2. Opacity controls (below XY, above Child)
                render_target_opacity_ui(t_score, "score")

                -- 3. Child Opacity tree
                render_target_child_tree(t_score, "score")
            end
            end_tree()
        end
    end

    ----------------------------------------------------------------------
    -- 5. DRAW CANVAS (Background, optional native tree node, default closed)
    ----------------------------------------------------------------------
    local t_draw = cfg_by_key("drawcanvas")
    if t_draw ~= nil then
        local vtag = get_vtag(t_draw)
        local draw_title = "Draw canvas (Background)" .. vtag
            .. (t_draw.active and "   [modified]" or "")
            .. ((t_draw.objs and #t_draw.objs > 0) and "" or "   (not found)")
            .. "##tree_draw"
        if begin_tree(draw_title, false) then
            if t_draw.objs ~= nil and #t_draw.objs > 0 then
                -- 1. Geometry: Scale
                local c_sc, v_sc = render_stepped_slider_scale("Scale", t_draw.sc or 1.0, 0.1, 4.0, 0.05, "draw_sc")
                if c_sc then
                    t_draw.sc = v_sc
                    t_draw.active = true
                    dirty = true
                end

                -- 2. Opacity controls (above Child)
                render_target_opacity_ui(t_draw, "draw")

                -- 3. Child Opacity tree
                render_target_child_tree(t_draw, "draw")
            end
            end_tree()
        end
    end

    ----------------------------------------------------------------------
    -- ACTION BUTTONS
    ----------------------------------------------------------------------
    imgui.separator()

    -- Save
    if imgui.button("Save##btn_save") then
        local ok, msg = save_cfg()
        save_msg = (ok and "[OK] " or "[FAIL] ") .. msg
        if ok then dirty = false end
        log("save " .. tostring(ok) .. " " .. msg)
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    -- Load Saved (placed right next to Save)
    if imgui.button("Load Saved##btn_load") then
        local ok = load_cfg()
        save_msg = ok and "[OK] Loaded saved configuration" or "[FAIL] No save file found"
        if ok then
            dirty = false
            for _, t in ipairs(TARGETS) do
                t.applied = false
                t.opApplied = nil
                t.scApplied = nil
                t.opaqueApplied = nil
            end
            invalidate_all_opaque()
        end
        log("load saved " .. tostring(ok))
    end

    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end

    -- Reset ALL to base (Restores base state: offsets=0, scale=0, opacity=0.95, cascade=ON. DOES NOT write to json until Save is pressed)
    if imgui.button("Reset ALL to base##btn_reset_all") then
        for _, t in ipairs(TARGETS) do
            local d = DEFAULTS[t.key]
            if d ~= nil then
                t.x = d.x
                t.y = d.y
                t.active = true
                t.sc = d.sc or 1.0
                t.sdx = d.sdx or 0.0
                t.sdy = d.sdy or 0.0
                t.hsc = 1.0
                t.wx = 0.0
                t.wy = 0.0
                t.wsc = 1.0
                t.cascade = true
                t.op = 0.95
                t.saved_children_op = nil
                t.opApplied, t.scApplied = nil, nil
                t.cascadeApplied = nil
            end
            if t.items ~= nil then
                for _, e in ipairs(t.items) do
                    restore(e)
                    if e.node ~= nil then
                        local function reset_node_base(n)
                            n.op = 0.95
                            n.cascade = true
                            n.applied_op = nil
                            pcall(function() n.o:SetRenderOpacity(0.95) end)
                            pcall(function() n.o:call("SetRenderOpacity", 0.95) end)
                            if n.children ~= nil then
                                for _, c in ipairs(n.children) do reset_node_base(c) end
                            end
                        end
                        reset_node_base(e.node)
                    else
                        pcall(function() e.o:SetRenderOpacity(0.95) end)
                        pcall(function() e.o:call("SetRenderOpacity", 0.95) end)
                        e.applied_op = 0.95
                    end
                end
            end
            if t.key == "ladder" and t.whisky_item ~= nil and t.whisky_item.o ~= nil then
                pcall(function() t.whisky_item.o:SetRenderTranslation({ X = 0.0, Y = 0.0 }) end)
                pcall(function() t.whisky_item.o:SetRenderScale({ X = 1.0, Y = 1.0 }) end)
                pcall(function() t.whisky_item.o:SetRenderOpacity(0.95) end)
                pcall(function() t.whisky_item.o:call("SetRenderOpacity", 0.95) end)
            end
            t.applied = true
        end
        invalidate_all_opaque()
        dirty = true
        save_msg = "[RESET] Reset to base (Opacity: 0.95, Child: ON. Press 'Save' if you want to overwrite ac8_ladder.json)"
        if enable_debug_dump then log("Reset ALL to base executed") end
    end

    -- Emergency UI Display Button (Archived Instant HIDE & SHOW ALL sequence)
    if imgui.button("Emergency: Force Show ALL HUD##btn_emergency_hud") then
        trigger_instant_cycle = true
        cycle_frame = 0
        save_msg = "[EMERGENCY] Cycle triggered: collapsing and awakening all HUD elements"
        if enable_debug_dump then log("Emergency HUD cycle triggered") end
    end
    imgui.text("Emergency recovery: Toggles HUD off & on in 4 frames to wake up all dormant HUD elements")

    -- Debug Dump Checkbox
    local changed_dbg, val_dbg = imgui.checkbox("Enable Debug Dump Logging##cb_dbg", enable_debug_dump)
    if changed_dbg then
        enable_debug_dump = val_dbg
        if enable_debug_dump then
            log("=== Debug Dump Logging ENABLED ===")
        else
            if FH ~= nil then pcall(function() FH:close() end); FH = nil end
        end
    end
    imgui.text("When checked, slider movements and events are dumped to log")

    -- Restore Missing HUD
    if imgui.button("Restore Missing HUD (Diagnose & Reset)##btn_smart_restore") then
        local ok, msg = smart_restore_hud()
        save_msg = ok and ("[SUCCESS] " .. msg) or ("[FAILED] " .. msg)
    end
    imgui.text("If HUD/Attitude disappears, click above to diagnose & restore")

    -- Reload targets
    if imgui.button("Reload targets (after menu / mission change)##btn_reload_targets") then
        current_mf = nil
        is_flight_active(true)
        for _, t in ipairs(TARGETS) do
            t.objs, t.items = nil, nil
            t.applied = false
        end
        resolve_all(true)
        log("reload targets")
    end

    imgui.text(dirty and "UNSAVED CHANGES" or "saved")
    if save_msg ~= "" then imgui.text(save_msg) end
end

local ui_err_logged = false
local function ui_safe()
    local ok, err = pcall(ui_body)
    if not ok then
        if not ui_err_logged then
            ui_err_logged = true
            log("!! UI Error: " .. tostring(err))
        end
        imgui.text("UI ERROR: " .. tostring(err))
    end
end

local ui_ok = pcall(function() uevr.sdk.callbacks.on_draw_ui(ui_safe) end)
log("on_draw_ui  = " .. tostring(ui_ok)
    .. "   button = " .. tostring(HAS_BUTTON)
    .. "   json = " .. tostring(HAS_JSON))

--------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------
log("===  ===")
log("   = " .. tostring(load_cfg()))

log("===  ===")
-- resolve_all MainFlight

--------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------
pcall(function()
    uevr.sdk.callbacks.on_pre_slate_draw_window_render_thread(function()
        if is_flight_active() then
            apply()
        end
    end)
end)

-- --------------------------------------------------------------------------
-- Reload targets
-- --------------------------------------------------------------------------
local last_pawn_ptr = nil
local function check_scene_transition()
    local pawn = nil
    pcall(function() pawn = api:get_local_pawn(0) end)
    if not pawn then
        pcall(function()
            local pc = api:get_player_controller(0)
            if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
        end)
    end

    if pawn ~= last_pawn_ptr then
        last_pawn_ptr = pawn
        return true, (pawn ~= nil)
    end
    return false, (pawn ~= nil)
end

local function has_missing_active_targets()
    for _, t in ipairs(TARGETS) do
        if t.active and (t.items == nil or #t.items == 0) then
            return true
        end
    end
    return false
end

local was_flight_active = false
local last_retry_tick = -999
local retry_count = 0

pcall(function()
    uevr.sdk.callbacks.on_post_engine_tick(function()
        ticks = ticks + 1

        -- Emergency Instant HIDE & SHOW ALL sequence
        if trigger_instant_cycle then
            cycle_frame = cycle_frame + 1
            if cycle_frame == 1 then
                -- Frame 1: Collapse all MainFlight HUD widgets
                set_hud_visibility_all(true)
            elseif cycle_frame >= 4 then
                -- Frame 4: Restore Visible (Turn ON -> All hidden/dormant elements awaken!)
                set_hud_visibility_all(false)
                trigger_instant_cycle = false
                cycle_frame = 0
                current_mf = nil
                is_flight_active(true)
                resolve_all(true)
                apply()
            end
        end

        local scene_changed, has_pawn = check_scene_transition()
        local flight_now = is_flight_active(scene_changed and has_pawn)

        -- 1.  /  / 
        if flight_now ~= was_flight_active then
            was_flight_active = flight_now
            if flight_now then
                log(">> MainFlightHUD")
                for _, t in ipairs(TARGETS) do
                    t.objs, t.items = nil, nil
                    t.applied = false
                end
                resolve_all(true)
                last_retry_tick = ticks
                retry_count = 0
            else
                log(">> /HUD")
                for _, t in ipairs(TARGETS) do
                    t.objs, t.items = nil, nil
                    t.applied = false
                end
                current_mf = nil
                return
            end
        end

        -- 2. ///
        if not flight_now then
            return
        end

        -- 3. Pawn/
        if scene_changed and has_pawn then
            log(">> Pawn/HUD")
            for _, t in ipairs(TARGETS) do
                t.objs, t.items = nil, nil
                t.applied = false
            end
            resolve_all(true)
            last_retry_tick = ticks
            retry_count = 0
        end

        -- 4. 300.52010
        if has_missing_active_targets() and retry_count < 20 and (ticks - last_retry_tick >= 30) then
            retry_count = retry_count + 1
            last_retry_tick = ticks
            resolve_all(false)
        end

        -- 5. 
        apply()

        -- 6. 30
        if ticks % RESCAN_EVERY == 0 then pcall(rescan_one) end
    end)
end)
