-- Final HUD placements: campaign rows, velocity/forward locators, wingman/radar,
-- loading indicator and bomb attachments. Presentation defaults below run once
-- per Lua session; recurring placement services have their own bounded cadence.
-- AC8 VR: register sections; Core starts them in explicit dependency order.

local HUD_PRESENTATION = {
    enabled = true,
    depth = 1.0,
    scale = 1.0,
    curvature = 113.625,
}

local registry = rawget(_G, 'AC8VRModules')
if not registry then
    registry = {sections={}, state='waiting', completed={}}
    rawset(_G, 'AC8VRModules', registry)
end

local cachedCanvasVirtualSize = nil
local cachedCanvasCenter = nil
local cachedLadderBase = nil
local lastSizeCheckTick = -1000
local sblCdo = nil

local function getCanvasVirtualSize()
    local R = rawget(_G, 'AC8Runtime')
    local nowTick = (R and R.tick) or 0
    if cachedCanvasVirtualSize and cachedCanvasCenter and (nowTick - lastSizeCheckTick) < 60 then
        return cachedCanvasVirtualSize, cachedCanvasCenter
    end
    lastSizeCheckTick = nowTick

    local measured = nil
    pcall(function()
        local root = (R and R.context and R.context.root) or (R and R.hudLayoutRefs and R.hudLayoutRefs.root)
        if root and (R and R.isLiveObject and R.isLiveObject(root)) then
            local geom = root:GetPaintSpaceGeometry() or root:GetCachedGeometry()
            if not sblCdo or not (R and R.isLiveObject and R.isLiveObject(sblCdo)) then
                local sblCls = uevr.api:find_uobject('Class /Script/UMG.SlateBlueprintLibrary')
                sblCdo = sblCls and sblCls:get_class_default_object() or nil
            end
            if geom and sblCdo then
                local s = sblCdo:GetLocalSize(geom)
                if s and type(s.X) == 'number' and s.X > 100 and type(s.Y) == 'number' and s.Y > 100 then
                    measured = { X = s.X, Y = s.Y }
                end
            end
        end
    end)

    if measured then
        cachedCanvasVirtualSize = measured
        cachedCanvasCenter = { X = measured.X * 0.5, Y = measured.Y * 0.5 }
        if R then
            local prevW = R.cachedCanvasVirtualSize and R.cachedCanvasVirtualSize.X or 0
            R.cachedCanvasVirtualSize = cachedCanvasVirtualSize
            R.cachedCanvasCenter = cachedCanvasCenter
            R.getCanvasVirtualSize = getCanvasVirtualSize
            if prevW ~= measured.X and R.syncLocatorConfigToDLL then
                pcall(R.syncLocatorConfigToDLL)
            end
        end
        return cachedCanvasVirtualSize, cachedCanvasCenter
    end

    if cachedCanvasVirtualSize and cachedCanvasCenter then
        return cachedCanvasVirtualSize, cachedCanvasCenter
    end

    local fallback = { X = 3840.0, Y = 2160.0 }
    local fallbackCenter = { X = 1920.0, Y = 1080.0 }
    return fallback, fallbackCenter
end

assert(not registry.sections['inherited_hud'], 'Duplicate AC8 VR section: inherited_hud')
registry.sections['inherited_hud'] = function(R)

AC8Runtime.inheritedSetup[#AC8Runtime.inheritedSetup+1] = function()
do
-- Flat2VR Modding Community and Discord: inherited HUD layout discovery & BlurEffectBox clear.
(function(uevr, json, print)

local SAFE_REF_W, SAFE_REF_H = 3840.0, 2160.0
local CANVAS_X,  CANVAS_Y    = SAFE_REF_W * 0.3125, SAFE_REF_H * (35.0 / 216.0)
local TW_X,      TW_Y        = -35, -55
local WHISKY_X,  WHISKY_Y    = 0, 0
local MAIN_X,    MAIN_Y      = 0, 0
local TACH_PULL, TACH_Y      = 0, 0
local RADAR_CIRCLE_DY        = 0

local SHIFT_VIA_PERSISTENT = true
local FIX_RADAR_CIRCLE     = false
local SINGLE_INSTANCE      = true

local RESET_LIST = {
    { key = "GunReticle",           pat = "GunReticle",           x = SAFE_REF_W * 0.5, y = SAFE_REF_H * 0.5 },
    { key = "Seeker",               pat = "Seeker",               x = 0,    y = 0    },
    { key = "Locator",              pat = "Locator",              x = 0,    y = 0    },
    { key = "ExplosivePredication", pat = "ExplosivePredication", x = -TW_X, y = -TW_Y },
    { key = "TargetSelectionDraw",  pat = "TargetSelectionDraw",  x = 0,    y = 0    },
}

local ASSERT_EVERY        = 20
local VALIDATE_EVERY      = 180
local MISSING_RETRY_EVERY = 20 * 60
local HB_EVERY            = 600
local SWEEP_RESIDUAL      = true
local SWEEP_THRESHOLD     = 600

local TACH_KX, TACH_KY = 0, 0
local TACH_NUDGE_X, TACH_NUDGE_Y = 0, 0

local function p(obj)
    if obj == nil then return "<nil>" end
    local ok, v = pcall(function() return obj:get_full_name() end)
    if not ok or v == nil then return "<no full_name>" end
    return v
end
local function short_name(obj)
    local nm = p(obj)
    if type(nm) == "string" then return nm:match("([^%.%/]+)$") or nm end
    return "<?>"
end
local function get_field(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[name] end)
    if not ok then return nil end
    return v
end
local function get_rt_xy(obj)
    if not AC8Runtime.isLiveObject(obj) then return nil, nil end
    if obj == nil then return nil, nil end
    local rt = get_field(obj, "RenderTransform")
    if rt == nil then return nil, nil end
    local t = get_field(rt, "Translation")
    if t == nil then return nil, nil end
    return get_field(t, "X"), get_field(t, "Y")
end

local function fast_rt(obj, tx, ty)
    if obj == nil or not AC8Runtime.isLiveObject(obj) then return false end
    pcall(function() obj:SetRenderTranslation({ X = tx, Y = ty }) end)
    return true
end

local function set_rt(obj, tx, ty, tag, quiet)
    if obj == nil or not AC8Runtime.isLiveObject(obj) then return false end
    pcall(function() obj:SetRenderTranslation({ X = tx, Y = ty }) end)
    return true
end

local function iter_children(w)
    local children = {}
    if w == nil or not AC8Runtime.isLiveObject(w) then return children end
    local okc, cc = pcall(function() return w.GetChildrenCount and w:GetChildrenCount() or 0 end)
    if okc and type(cc) == "number" and cc > 0 then
        for i = 0, cc - 1 do
            local ok2, c = pcall(function() return w:GetChildAt(i) end)
            if ok2 and c then table.insert(children, c) end
        end
    end
    -- Query UContentWidget (RetainerBox, SizeBox, Border) single child slot
    local okcnt, cnt = pcall(function() return w.GetContent and w:GetContent() end)
    if okcnt and cnt and AC8Runtime.isLiveObject(cnt) then
        table.insert(children, cnt)
    end
    if #children == 0 then
        local wt = get_field(w, "WidgetTree")
        if wt then
            local r = get_field(wt, "RootWidget")
            if r then table.insert(children, r) end
        end
    end
    return children
end

local function find_desc(root, target, maxd, exact)
    if root == nil or not AC8Runtime.isLiveObject(root) then return nil end
    local seen, found = {}, nil
    local function rec(w, d)
        if w == nil or found or d > maxd then return end
        local addr = tostring(w)
        if seen[addr] then return end
        seen[addr] = true
        local nm = short_name(w)
        local hit = exact and (nm == target) or (not exact and nm:find(target, 1, true) ~= nil)
        if hit then found = w; return end
        for _, c in ipairs(iter_children(w)) do rec(c, d + 1) end
    end
    rec(root, 0)
    return found
end

local function find_path(root, addr, maxd)
    if root == nil or addr == nil then return nil end
    local path = nil
    local function rec(w, d, acc)
        if w == nil or path or d > maxd then return end
        table.insert(acc, w)
        if tostring(w) == addr then path = acc; return end
        for _, c in ipairs(iter_children(w)) do rec(c, d + 1, acc) end
        if path == nil then table.remove(acc) end
    end
    rec(root, 0, {})
    return path
end

local function all_userwidgets()
    if uevr == nil or uevr.api == nil then return {} end
    local umg = uevr.api:find_uobject("Class /Script/UMG.UserWidget")
    if umg == nil then return {} end
    local ok, objs = pcall(function() return umg:get_objects_matching(false) end)
    if not ok or type(objs) ~= "table" then return {} end
    return objs
end

local function all_mainflights(uw)
    local out = {}
    for _, w in ipairs(uw) do
        local nm = p(w)
        if type(nm) == "string" and nm:find("WBP_HUD_Chronicle_MainFlight", 1, true)
            and not nm:find("Default__", 1, true) and not nm:find(".WidgetTree", 1, true) then
            table.insert(out, w)
        end
    end
    return out
end

local C = {
    ready  = false,
    keep   = nil, base = nil, wtsc = nil, maincv = nil, cp = nil,
    ts = nil, ta = nil, vicon = nil, vel = nil, whisky = nil,
    radar = {}, radar_main = nil,
    pins = {},
}

local R0_X = CANVAS_X - TW_X
local R0_Y = CANVAS_Y - TW_Y

local function capture_profiles(zero_big, quiet)
    local out = {}
    if C.cp == nil then return out end
    for _, tgt in ipairs({ "SpeedTachometerCenterPanel", "AltitudeTachometerCenterPanel", "WhiskyMarkPanel" }) do
        local t = find_desc(C.cp, tgt, 14, true)
        if t ~= nil then
            local path = find_path(C.cp, tostring(t), 14)
            if path ~= nil and #path > 2 then
                local prof = { key = tgt, layers = {}, sx = 0, sy = 0, cleared = 0 }
                for i = 2, #path - 1 do
                    local w = path[i]
                    local x, y = get_rt_xy(w)
                    local x0 = (type(x) == "number") and x or 0
                    local y0 = (type(y) == "number") and y or 0
                    local mag = math.abs(x0) + math.abs(y0)
                    if zero_big and (C.resid == nil or mag > C.resid.mag) then
                        C.resid = { x = x0, y = y0, mag = mag }
                    end
                    table.insert(prof.layers, { name = short_name(w), x = x0, y = y0 })
                    if zero_big and (math.abs(x0) > SWEEP_THRESHOLD or math.abs(y0) > SWEEP_THRESHOLD) then
                        fast_rt(w, 0, 0)
                        prof.max_layer = { name = short_name(w), x = x0, y = y0 }
                        prof.cleared = prof.cleared + 1
                    else
                        prof.sx = prof.sx + x0
                        prof.sy = prof.sy + y0
                    end
                end
                table.insert(out, prof)
            end
        end
    end
    return out
end

local function sweep_residual(quiet)
    if not SWEEP_RESIDUAL or C.cp == nil then return 0 end
    C.resid = nil
    C.prof = capture_profiles(true, quiet)
    local fixed = 0
    if C.prof ~= nil then
        for _, prof in ipairs(C.prof) do fixed = fixed + (prof.cleared or 0) end
    end
    return fixed
end

local function collect_radar(root)
    local out = {}
    if root == nil then return out end
    local seen = {}
    local function rec(w, d)
        if w == nil or d > 18 then return end
        local addr = tostring(w)
        if seen[addr] then return end
        seen[addr] = true
        if short_name(w):find("RadarCircleCanvasPanel", 1, true) then
            table.insert(out, w)
        end
        for _, c in ipairs(iter_children(w)) do rec(c, d + 1) end
    end
    rec(root, 0)
    return out
end

local function assert_pins(slow)
    local layoutActive = AC8Runtime and AC8Runtime.layoutEnabled
    local n = 0
    for _, pin in ipairs(C.pins) do
        if pin.obj ~= nil and (slow or not pin.slow) then
            -- When hud_layout is active, skip pins for elements dynamically managed by hud_layout
            local isConflict = layoutActive and (pin.dyn or pin.obj == C.whisky or pin.obj == C.cp)
            if not isConflict then
                local x, y = pin.x, pin.y
                local cx, cy = get_rt_xy(pin.obj)
                local okx = (type(cx) == "number" and math.abs(cx - x) < 1)
                local oky = (type(cy) == "number" and math.abs(cy - y) < 1)
                if not (okx and oky) then
                    fast_rt(pin.obj, x, y)
                end
                n = n + 1
            end
        end
    end
    if FIX_RADAR_CIRCLE then
        for _, w in ipairs(C.radar) do
            if w ~= nil then
                local cx, cy = get_rt_xy(w)
                if not (type(cx) == "number" and math.abs(cx) < 1
                        and type(cy) == "number" and math.abs(cy - RADAR_CIRCLE_DY) < 1) then
                    fast_rt(w, 0, RADAR_CIRCLE_DY)
                end
                n = n + 1
            end
        end
    end
    if slow then
        if C.keep ~= nil and AC8Runtime.isLiveObject(C.keep) then
            pcall(function() C.keep.RenderOpacity = 1.0 end)
            pcall(function() C.keep.Visibility = 0 end)
        end
        if C.base ~= nil and AC8Runtime.isLiveObject(C.base) then
            pcall(function() C.base.RenderOpacity = 1.0 end)
            pcall(function() C.base.Visibility = 0 end)
        end
    end
    return n
end

local function retry_missing()
    if C.wtsc == nil then return end
    for _, it in ipairs(RESET_LIST) do
        local pin = nil
        for _, q in ipairs(C.pins) do if q.tag == "RESET:" .. it.key then pin = q end end
        if pin ~= nil and pin.obj == nil then
            local w = find_desc(C.wtsc, it.pat, 12)
            if w ~= nil then
                pin.obj = w
                fast_rt(w, it.x, it.y)
            end
        end
    end
end

local effect_originals = {}
local effect_clear = true
local effect_retain = false
local function effect_poll()
    local ok, cmd = pcall(function() return json.load_file("AC8_VR-WorkshopEffectControls.json") or json.load_file("ac8_workshop_effect_controls.json") end)
    if ok and type(cmd) == "table" then
        if type(cmd.clearMaterial) == "boolean" then effect_clear = cmd.clearMaterial end
        if type(cmd.retainRendering) == "boolean" then effect_retain = cmd.retainRendering end
    end
end
local function effect_apply(blur)
    if not blur or not AC8Runtime.isLiveObject(blur) then return end
    local name = blur:get_full_name()
    if not name then return end
    local base = effect_originals[name]
    if not base then
        local ok, material = pcall(function() return blur:get_property("EffectMaterial") end)
        if not ok then return end
        local retain = blur:get_property("bRetainRender")
        if type(retain) ~= "boolean" then return end
        base = { material = material, retain = retain }
        effect_originals[name] = base
    end
    local wanted = nil
    if not effect_clear then wanted = base.material end
    local current = blur:get_property("EffectMaterial")
    if current ~= wanted then pcall(function() blur:SetEffectMaterial(wanted) end) end
    local retainWanted = base.retain
    if effect_retain then retainWanted = true end
    if blur:get_property("bRetainRender") ~= retainWanted then
        pcall(function() blur:SetRetainRendering(retainWanted) end)
        pcall(function() blur:RequestRender() end)
    end
end
effect_poll()

local refresh_remaining = 0
local function queue_hud_refresh(reason)
    refresh_remaining = 2
end
local function refresh_hud_layout()
    if not C.ready or refresh_remaining <= 0 then return end
    assert_pins(true)
    if C.keep and AC8Runtime.isLiveObject(C.keep) then
        pcall(function() C.keep:InvalidateLayoutAndVolatility() end)
        pcall(function() C.keep:ForceLayoutPrepass() end)
    end
    if C.workshopBlur and AC8Runtime.isLiveObject(C.workshopBlur) then
        pcall(function() C.workshopBlur:RequestRender() end)
    end
    refresh_remaining = refresh_remaining - 1
end
uevr.sdk.callbacks.on_lua_event(function(name, data)
    if name == 'AC8_HUD_Refresh' then queue_hud_refresh(data or 'glow_activation') end
end)

local function findActiveChronicleVelocityWidgets()
    local api = uevr and uevr.api
    if not api then return nil, nil end
    local ok, widgetClass = pcall(function() return api:find_uobject('Class /Script/UMG.Widget') end)
    if not ok or not widgetClass then return nil, nil end
    local candidates = nil
    pcall(function() candidates = widgetClass:get_objects_matching(false) end)
    if not candidates or type(candidates) ~= 'table' then return nil, nil end

    local R = rawget(_G, 'AC8Runtime')
    local function isUnderActiveMainFlight(w)
        local cur = w
        for _ = 1, 14 do
            if not cur then break end
            local fn = p(cur) or ''
            if fn:find('WBP_HUD_Chronicle_MainFlight', 1, true) then
                local inVp = false
                pcall(function() inVp = cur:IsInViewport() end)
                return inVp, cur
            end
            local okP, parent = pcall(function() return cur:GetParent() end)
            if not okP or not parent then break end
            cur = parent
        end
        return false, nil
    end

    local activeVel, activeIcon = nil, nil
    local fallbackVel, fallbackIcon = nil, nil

    for _, w in ipairs(candidates) do
        if R and R.isLiveObject and R.isLiveObject(w) then
            local fn = p(w) or ''
            local leaf = fn:match('%.([^%.]+)$')
            if fn:find('.WBP_ChroniclePersistent.', 1, true) then
                if leaf == 'Velocity' then
                    local inVp = isUnderActiveMainFlight(w)
                    if inVp and not activeVel then
                        activeVel = w
                    elseif not fallbackVel then
                        fallbackVel = w
                    end
                elseif leaf == 'VelocityIcon' then
                    local inVp = isUnderActiveMainFlight(w)
                    if inVp and not activeIcon then
                        activeIcon = w
                    elseif not fallbackIcon then
                        fallbackIcon = w
                    end
                end
            end
        end
    end

    local resVel = activeVel or fallbackVel
    local resIcon = activeIcon or fallbackIcon
    return resVel, resIcon
end

local function findWidgetInChroniclePersistent(leafName)
    if leafName == 'Velocity' or leafName == 'VelocityIcon' then
        local v, vi = findActiveChronicleVelocityWidgets()
        if leafName == 'Velocity' then return v end
        if leafName == 'VelocityIcon' then return vi end
    end
    local api = uevr and uevr.api
    if not api then return nil end
    local ok, widgetClass = pcall(function() return api:find_uobject('Class /Script/UMG.Widget') end)
    if not ok or not widgetClass then return nil end
    local candidates = nil
    pcall(function() candidates = widgetClass:get_objects_matching(false) end)
    if not candidates or type(candidates) ~= 'table' then return nil end
    for _, w in ipairs(candidates) do
        if AC8Runtime.isLiveObject(w) then
            local fn = p(w) or ''
            local leaf = fn:match('%.([^%.]+)$')
            if leaf == leafName and fn:find('.WBP_ChroniclePersistent.', 1, true) then
                return w
            end
        end
    end
    return nil
end

local function discover()
    C.keep = nil; C.base = nil; C.wtsc = nil; C.maincv = nil; C.cp = nil
    C.ts = nil; C.ta = nil; C.vicon = nil; C.vel = nil; C.whisky = nil; C.altimeter = nil; C.campaign = nil
    C.radar = {}; C.radar_main = nil; C.pins = {}
    C.resid = nil; C.prof = nil

    local keep, keep_addr = nil, nil
    if AC8Runtime.context and AC8Runtime.context.root and AC8Runtime.isLiveObject(AC8Runtime.context.root)
       and (AC8Runtime.context.rootName or ''):match('^WBP_HUD_Chronicle_MainFlight') then
        keep = AC8Runtime.context.root
        keep_addr = tostring(keep)
        pcall(function()
            if not keep:IsInViewport() then keep:AddToViewport() end
        end)
    else
        local uw = all_userwidgets()
        local mfs = all_mainflights(uw)
        if #mfs == 0 then return false end
        for _, mf in ipairs(mfs) do
            local inv = nil
            pcall(function() inv = mf:IsInViewport() end)
            if inv == true then keep = mf; keep_addr = tostring(mf); break end
        end
        if keep == nil then
            keep = mfs[1]; keep_addr = tostring(mfs[1])
            pcall(function() keep:AddToViewport() end)
        end
        if #mfs > 1 and SINGLE_INSTANCE then
            for _, mf in ipairs(mfs) do
                if tostring(mf) ~= keep_addr then
                    local inv = nil
                    pcall(function() inv = mf:IsInViewport() end)
                    if inv == true then pcall(function() mf:RemoveFromViewport() end) end
                end
            end
        end
    end
    if not keep or not AC8Runtime.isLiveObject(keep) then return false end
    C.keep = keep

    pcall(function() keep.RenderOpacity = 1.0 end)
    pcall(function() keep:SetRenderOpacity(1.0) end)
    pcall(function() keep.Visibility = 0 end)
    pcall(function() keep:SetVisibility(0) end)

    local base = find_desc(keep, "BaseCanvas", 6, true)
    if base == nil then return false end
    C.base = base
    pcall(function() base.RenderOpacity = 1.0 end)
    pcall(function() base.Visibility = 0 end)

    local blur = find_desc(base, "BlurEffectBox", 8)
    if blur then
        C.workshopBlur = blur
        pcall(effect_apply, blur)
        pcall(function() blur.Visibility = 0 end)
        pcall(function() blur.RenderOpacity = 1.0 end)
    end

    local wtsc = find_desc(base, "WorldToScreenDrawCanvas", 3, true)
    if wtsc == nil then return false end
    C.wtsc      = wtsc
    C.maincv    = find_desc(base, "MainCanvas", 3, true)
    local cp    = (keep and R.objectCall(keep, 'get_property', 'WBP_ChroniclePersistent'))
        or find_desc(wtsc, "ChroniclePersistent", 3)
    C.cp        = cp
    if cp and R.isLiveObject(cp) then
        C.altimeter = R.objectCall(cp, 'get_property', 'Altimeter') or find_desc(cp, "Altimeter", 12, true) or findWidgetInChroniclePersistent("Altimeter")
        C.whisky    = R.objectCall(cp, 'get_property', 'WhiskyMarkPanel') or find_desc(cp, "WhiskyMarkPanel", 12, true) or findWidgetInChroniclePersistent("WhiskyMarkPanel")
        C.vel       = R.objectCall(cp, 'get_property', 'Velocity') or find_desc(cp, "Velocity", 12, true) or findWidgetInChroniclePersistent("Velocity")
        C.vicon     = R.objectCall(cp, 'get_property', 'VelocityIcon') or find_desc(cp, "VelocityIcon", 12, true) or findWidgetInChroniclePersistent("VelocityIcon")
        C.ts        = R.objectCall(cp, 'get_property', 'SpeedTachometerCenterPanel') or find_desc(cp, "SpeedTachometerCenterPanel", 14, true)
        C.ta        = R.objectCall(cp, 'get_property', 'AltitudeTachometerCenterPanel') or find_desc(cp, "AltitudeTachometerCenterPanel", 14, true)
    else
        C.altimeter = find_desc(wtsc, "Altimeter", 12, true) or findWidgetInChroniclePersistent("Altimeter")
        C.whisky    = find_desc(wtsc, "WhiskyMarkPanel", 12, true) or findWidgetInChroniclePersistent("WhiskyMarkPanel")
        C.vel       = find_desc(wtsc, "Velocity", 12, true) or findWidgetInChroniclePersistent("Velocity")
        C.vicon     = find_desc(wtsc, "VelocityIcon", 12, true) or findWidgetInChroniclePersistent("VelocityIcon")
        C.ts        = find_desc(wtsc, "SpeedTachometerCenterPanel", 14, true)
        C.ta        = find_desc(wtsc, "AltitudeTachometerCenterPanel", 14, true)
    end
    C.campaign  = find_desc(C.keep, "CampaignInfo", 14, false)
    C.info      = find_desc(C.keep, "WBP_PlayerStateWidget", 14, false) or find_desc(C.keep, "PlaneCanvas", 14, false) or find_desc(C.keep, "PlayerStatus", 14, false)
    C.radar     = collect_radar(C.maincv)
    if #C.radar > 0 then
        for _, w in ipairs(C.radar) do
            local v = get_field(w, "Visibility")
            if v == nil or v == 0 or v == 3 or v == 4 then C.radar_main = w; break end
        end
        if C.radar_main == nil then C.radar_main = C.radar[1] end
    end

    AC8Runtime.hudLayoutRefs = {
        radar     = C.radar_main,
        root      = C.keep,
        wtsc      = C.wtsc,
        info      = C.info,
        score     = C.campaign,
        maincv    = C.maincv,
        cp        = C.cp,
        vicon     = C.vicon,
        vel       = C.vel,
        altimeter = C.altimeter,
        whisky    = C.whisky,
        ts        = C.ts,
        ta        = C.ta,
        campaign  = C.campaign,
        radarList = C.radar,
        epoch     = C.hudEpoch
    }

    sweep_residual(false)

    table.insert(C.pins, { obj = C.wtsc, x = TW_X, y = TW_Y, tag = "AC8 layout" })
    if C.cp ~= nil and SHIFT_VIA_PERSISTENT then
        table.insert(C.pins, { obj = C.cp, x = R0_X, y = R0_Y, tag = "AC8 layout", dyn = true })
    end
    if C.maincv ~= nil then
        table.insert(C.pins, { obj = C.maincv, x = MAIN_X, y = MAIN_Y, tag = "AC8 layout" })
    end
    if C.whisky ~= nil then table.insert(C.pins, { obj = C.whisky, x = WHISKY_X, y = WHISKY_Y, tag = "WhiskyMarkPanel(W)" }) end
    if C.ts     ~= nil then table.insert(C.pins, { obj = C.ts,     x = TACH_PULL + TACH_KX + TACH_NUDGE_X, y = TACH_Y + TACH_KY + TACH_NUDGE_Y, tag = "AC8 layout" }) end
    if C.ta     ~= nil then table.insert(C.pins, { obj = C.ta,     x = -TACH_PULL + TACH_KX + TACH_NUDGE_X, y = TACH_Y + TACH_KY + TACH_NUDGE_Y, tag = "AC8 layout" }) end
    for _, it in ipairs(RESET_LIST) do
        local w = find_desc(wtsc, it.pat, 12)
        table.insert(C.pins, { obj = w, x = it.x, y = it.y, tag = "RESET:" .. it.key, slow = true })
    end

    for _, pin in ipairs(C.pins) do
        if pin.obj ~= nil and not pin.dyn then
            set_rt(pin.obj, pin.x, pin.y, pin.tag, false)
        end
    end
    if C.cp ~= nil and SHIFT_VIA_PERSISTENT then
        set_rt(C.cp, R0_X, R0_Y, "AC8 layout", false)
    else
        table.insert(C.pins, { obj = C.wtsc, x = CANVAS_X, y = CANVAS_Y, tag = "AC8 layout" })
    end

    pcall(function() wtsc.Visibility = 0 end)
    pcall(function() wtsc.RenderOpacity = 1.0 end)
    if C.maincv ~= nil then
        pcall(function() C.maincv.Visibility = 0 end)
        pcall(function() C.maincv.RenderOpacity = 1.0 end)
    end

    assert_pins(true)
    C.ready = true
    queue_hud_refresh("initial_layout")
    return true
end

rawset(_G, 'AC8_RefreshHUDCache', function()
    C.ready = false
    local ok = discover()
    if ok then
        if rawget(_G, 'AC8_RefreshUICache') then pcall(rawget(_G, 'AC8_RefreshUICache'), true) end
    end
    return ok
end)
if type(AC8Runtime) == 'table' then
    AC8Runtime.refreshHUDCache = function()
        C.ready = false
        local ok = discover()
        if ok then
            if type(AC8Runtime.refreshUICache) == 'function' then pcall(AC8Runtime.refreshUICache, true) end
        end
        return ok
    end
end

local function validate()
    for _, e in ipairs({ C.keep, C.base, C.wtsc, C.cp }) do
        if e ~= nil then
            if not AC8Runtime.isLiveObject(e) then
                C.ready = false
                return false
            end
        end
    end
    return true
end

local CAM_ANIM_KILL  = true
local CAM_KILL_EVERY = 1
local function cam_get_pawn()
    local ok, p = pcall(function() return uevr.api:get_local_pawn(0) end)
    if ok and p ~= nil and AC8Runtime.isLiveObject(p) then return p end
    local ok2, p2 = pcall(function() return uevr.api:get_player_pawn() end)
    if ok2 and p2 ~= nil and AC8Runtime.isLiveObject(p2) then return p2 end
    return nil
end

local function cam_kill_anims()
    local pm = nil
    pcall(function()
        local a = uevr and uevr.api
        if a == nil then return end
        local ctrl = nil
        local pawn = cam_get_pawn()
        if pawn ~= nil then
            pcall(function() ctrl = pawn.Controller end)
            if ctrl == nil then pcall(function() ctrl = pawn:get_Controller() end) end
        end
        if ctrl == nil then
            pcall(function()
                if a.get_player_controller ~= nil then ctrl = a:get_player_controller(0) end
            end)
        end
        if ctrl == nil or not AC8Runtime.isLiveObject(ctrl) then return end
        pcall(function() pm = ctrl.PlayerCameraManager end)
        if pm == nil then pcall(function() pm = ctrl:get_PlayerCameraManager() end) end
    end)
    if pm == nil or not AC8Runtime.isLiveObject(pm) then return false end
    pcall(function() pm:StopAllCameraAnims(true) end)
    pcall(function() pm:StopAllCameraShakes(true) end)
    return true
end

local frame_n = 0
local retry_gap = 10
local function on_frame()
    local intent = rawget(_G, 'AC8_CinematicIntent')
    if intent then intent.hudAcknowledged = true end
    local context = AC8Runtime.context
    if C.hudEpoch ~= context.epoch then C.hudEpoch = context.epoch; C.ready = false; retry_gap = 10; frame_n = 0 end
    if not context.flight then return end
    frame_n = frame_n + 1
    if rawget(_G, 'AC8Runtime') and AC8Runtime.profileCount then AC8Runtime.profileCount('inheritedHudTick') end
    if not C.ready then
        if frame_n % retry_gap == 0 then
            if discover() then
                retry_gap = 10
            else
                retry_gap = math.min(retry_gap * 2, 60)
            end
        end
        return
    end
    if rawget(_G, 'AC8Runtime') and AC8Runtime.layoutEnabled then
        -- Modern hud_layout manages all positioning and dynamic safe margins.
        -- Completely disable legacy periodic pin assertions and layout invalidations.
        return
    end
    if frame_n % 8 == 0 then refresh_hud_layout() end
    if frame_n % ASSERT_EVERY == 0 then assert_pins() end
    if frame_n % VALIDATE_EVERY == 0 then if not validate() then return end end
    if frame_n % MISSING_RETRY_EVERY == 0 then retry_missing() end
    if frame_n % HB_EVERY == 0 then assert_pins(true) end
    if CAM_ANIM_KILL and not (intent and intent.active) and frame_n % CAM_KILL_EVERY == 0 then
        cam_kill_anims()
    end
end

local cbs = uevr and uevr.sdk and uevr.sdk.callbacks
if cbs and cbs.on_post_engine_tick then
    pcall(function() cbs.on_post_engine_tick(on_frame) end)
end

end)(AC8Runtime.host('layout', 'ac8_hud_inspect.lua'), AC8Runtime.json, AC8Runtime.log)
end
end

end

assert(not registry.sections['hud_layout'], 'Duplicate AC8 VR section: hud_layout')
registry.sections['hud_layout'] = function(R)
-- Own final VR HUD positioning and ordered inherited layout services.
local presentation = {done=false, status='waiting'}
R.hudPresentationDefaults = presentation
local function applyPresentationDefaults(force)
    if presentation.done and not force then return end
    local presCfg = R.customHUDConfig and R.customHUDConfig.hudPresentation
    local isEnabled = false
    if presCfg and type(presCfg.enabled) == 'boolean' then
        isEnabled = presCfg.enabled
    elseif HUD_PRESENTATION and type(HUD_PRESENTATION.enabled) == 'boolean' then
        isEnabled = HUD_PRESENTATION.enabled
    end
    if not isEnabled then
        presentation.done = true
        presentation.status = 'disabled by options (using user UEVR config.txt)'
        return
    end
    local depth = (presCfg and tonumber(presCfg.distance)) or HUD_PRESENTATION.depth or 1.0
    local scale = (presCfg and tonumber(presCfg.size)) or HUD_PRESENTATION.scale or 1.0
    local curvature = (presCfg and tonumber(presCfg.curvature)) or HUD_PRESENTATION.curvature or 113.625
    local overlayType = (presCfg and presCfg.curvedOverlay == false) and 0 or 1
    local settings = {
        {key='UI_Distance', value=depth, min=.01, max=100},
        {key='UI_Size', value=scale, min=.01, max=100},
        {key='UI_Cylinder_Angle', value=curvature, min=1, max=359},
        {key='UI_OverlayType', value=overlayType, min=0, max=1},
    }
    for _, setting in ipairs(settings) do
        local v = setting.value
        if type(v) ~= 'number' or v ~= v or v < setting.min or v > setting.max then
            presentation.done = true; presentation.status = 'invalid ' .. setting.key
            R.errors.hudPresentationDefaults = presentation.status; return
        end
    end
    local ci = rawget(_G, 'AC8_CinematicIntent')
    if ci and (ci.maskActive or ci.hangarActive or ci.recoveringUI or ci.guardForced or
       (ci.saved and next(ci.saved) ~= nil) or (ci.hangarSaved and next(ci.hangarSaved) ~= nil)) then return end
    local function read(key)
        local ok, v = pcall(function() return uevr.params.vr:get_mod_value(key) end)
        local n = ok and tonumber(v)
        if n and n == n and math.abs(n) < 1e9 then return n end
    end
    local before = {}
    for _, setting in ipairs(settings) do
        local value = read(setting.key)
        if value == nil then presentation.status = 'waiting for UEVR UI settings'; return end
        before[setting.key] = value
    end
    presentation.done = true
    local changed = {}
    for _, setting in ipairs(settings) do
        if math.abs(before[setting.key] - setting.value) > .0001 then
            changed[#changed+1] = setting.key
            local ok = pcall(function() uevr.params.vr.set_mod_value(setting.key, tostring(setting.value)) end)
            local actual = read(setting.key)
            if not ok or not actual or math.abs(actual - setting.value) > .0001 then
                for i = #changed, 1, -1 do
                    local key = changed[i]; pcall(function() uevr.params.vr.set_mod_value(key, tostring(before[key])) end)
                end
                presentation.status = 'UEVR write failed; previous values restored where possible'
                R.errors.hudPresentationDefaults = presentation.status; return
            end
        end
    end
    presentation.status = 'applied once; UEVR menu changes now take priority'
end
R.applyPresentationDefaults = applyPresentationDefaults
applyPresentationDefaults()
R.host('layout', 'HUD presentation defaults').sdk.callbacks.on_post_engine_tick(applyPresentationDefaults)

AC8Runtime.layoutEnabled = true
for i, setup in ipairs(AC8Runtime.inheritedSetup) do
    local ok, err = pcall(setup)
    if not ok then AC8Runtime.errors['inherited layout ' .. i] = tostring(err) end
end
AC8Runtime.inheritedSetup = {}

-- Forward Locator (WBP_LocatorWidget FowardLocatorOffset)
do
(function(uevr, json, print)
    local old = rawget(_G, 'AC8_ForwardLocatorTest')
    if old then old.stopped = true; if old.restore then old.restore() end end
    local S = {version=4, enabled=true, stopped=false, y=-600, ticks=0, status='waiting for locator widget'}
    rawset(_G, 'AC8_ForwardLocatorTest', S)
    local function call(o, k, ...)
        if o ~= uevr.api and not AC8Runtime.isLiveObject(o) then return nil end
        if not o then return nil end
        local ok, v = pcall(function(...) return o[k](o, ...) end, ...); if ok then return v end
    end
    local function full(o) return call(o, 'get_full_name') end
    local function read(o)
        local ok, v = pcall(function()
            local p = o:get_property('FowardLocatorOffset')
            if type(p.X) ~= 'number' or type(p.Y) ~= 'number' then return nil end
            return {X=p.X, Y=p.Y}
        end)
        if ok then return v end
    end
    local function same(a, b) return a and b and math.abs(a.X - b.X) < 0.5 and math.abs(a.Y - b.Y) < 0.5 end
    local function set(o, p)
        if same(read(o), p) then return true end
        pcall(function() o:set_property('FowardLocatorOffset', p) end)
        return same(read(o), p)
    end
    function S.restore()
        if S.widget and full(S.widget) == S.name and S.original then
            local current = read(S.widget)
            if same(current, S.applied) and not set(S.widget, S.original) then return false end
        end
        S.widget = nil; S.name = nil; S.original = nil; S.applied = nil; S.verified = false
        return true
    end
    local function discard() S.widget = nil; S.name = nil; S.original = nil; S.applied = nil; S.verified = false end
    local function apply()
        if S.stopped then return end
        S.ticks = S.ticks + 1
        if not (AC8Runtime.context and AC8Runtime.context.flight) then discard(); S.status = 'inactive'; return end
        local hud = AC8Runtime.context.hud
        local hn = AC8Runtime.context.hudName or ''
        local ci = rawget(_G, 'AC8_CinematicIntent')
        if not hn:match('^LiveMainHUDParent%w*_C ') then discard(); S.status = 'inactive'; return end
        if not S.enabled or (ci and ci.cameraLocked) then
            S.restore(); S.status = 'inactive'; return
        end
        local canvas = call(hud, 'get_property', 'DynamicCanvas')
        local cn = full(canvas)
        if cn ~= S.canvasName then discard(); S.canvasName = cn end
        if S.widget and full(S.widget) ~= S.name then discard() end
        if not S.widget then
            for i = 0, math.min(call(canvas, 'GetChildrenCount') or 0, 64) - 1 do
                local w = call(canvas, 'GetChildAt', i); local n = full(w) or ''
                if n:match('^WBP_HUD_DynamicWidget_Parts_Locator_000_C ') and n:match('%.WBP_LocatorWidget$') then
                    local initial = read(w)
                    if initial then S.widget = w; S.name = n; S.original = initial; break end
                end
            end
        end
        if not S.widget then S.status = 'locator widget unavailable'; return end
        local he = AC8Runtime.customHUDConfig and AC8Runtime.customHUDConfig.hudElements
        local lcfg = he and he.ladder or {}
        local noseCfg = he and he.nose or {}
        local userX = (tonumber(lcfg.x) or 0) + (tonumber(noseCfg.x) or 0)
        local userY = (tonumber(lcfg.y) or 0) + (tonumber(noseCfg.y) or 0)

        local canvasSize, _ = getCanvasVirtualSize()
        local safeH = canvasSize and math.min(canvasSize.Y, canvasSize.X * (9.0 / 16.0)) or 2160.0
        local safeW = canvasSize and math.min(canvasSize.X, canvasSize.Y * (16.0 / 9.0)) or 3840.0
        local marginX = canvasSize and math.max(0.0, (canvasSize.X - safeW) * 0.5) or 0.0

        -- Lift forward boresight arrow from native bottom dashboard towards screen center (FPM / Whisky mark)
        -- Baseline matching FPM screen center coordinates: X = -1232.0, Y = -322.0
        -- On Ultrawide, add marginX shift to keep aligned with screen center
        local forwardShiftY = -322.0
        local boresightX = -1232.0 + marginX
        local wanted = {X = S.original.X + boresightX + userX, Y = S.original.Y + forwardShiftY - userY}
        if S.verified and S.applied and same(S.applied, wanted) then return end
        S.verified = set(S.widget, wanted)
        if S.verified then
            S.applied = wanted; S.status = 'forward arrow correction applied'
        else
            S.status = 'forward arrow write pending'
        end
    end
    uevr.sdk.callbacks.on_post_engine_tick(function()
        local ok, err = pcall(apply)
        if not ok then S.enabled = false; S.restore(); S.status = tostring(err) end
    end)
    pcall(function() uevr.sdk.callbacks.on_script_reset(S.restore) end)
end)(AC8Runtime.host('layout', 'forward_locator.lua'), AC8Runtime.json, AC8Runtime.log)
end

-- Offscreen Locator Canvas (LowestPriorityDynamicDrawCanvas)
do
local R = AC8Runtime; local host = R.host('layout', 'fixed arrow and wingman status placement')
local S = {version=62, epoch=-1, x=-180, scale=.96, nextControls=0, attempts=0, writes=0, failures=0}
R.offscreenLocatorMargin = S
local function call(o, k, ...)
    if not o or (o ~= uevr.api and not R.isLiveObject(o)) then return end
    local ok, v = pcall(function(...) return o[k](o, ...) end, ...); if ok then return v end
end
local function full(o) return call(o, 'get_full_name') end
local function xy(v)
    local ok, x, y = pcall(function() return v.X, v.Y end)
    if ok and type(x) == 'number' and type(y) == 'number' and x == x and y == y then return {X=x, Y=y} end
end
local function same(a, b) return a and b and math.abs(a.X - b.X) < .01 and math.abs(a.Y - b.Y) < .01 end
local function translation(o)
    if not R.isLiveObject(o) then return end
    local ok, v = pcall(function() return o:get_property('RenderTransform').Translation end)
    return ok and xy(v)
end
local function put(o, v) call(o, 'SetRenderTranslation', v); return same(translation(o), v) end
local function scale(o)
    local ok, v = pcall(function() return o:get_property('RenderTransform').Scale end)
    return ok and xy(v)
end
local function pivot(o) return xy(call(o, 'GetRenderTransformPivot') or call(o, 'get_property', 'RenderTransformPivot')) end
local function putScale(o, v) call(o, 'SetRenderScale', v); return same(scale(o), v) end
local function restore(row)
    if row.widget and R.isLiveObject(row.widget) and full(row.widget) == row.name and same(translation(row.widget), row.last) then
        put(row.widget, row.original)
    end
    if row.widget and R.isLiveObject(row.widget) then
        if row.originalScale and same(scale(row.widget), row.lastScale) then putScale(row.widget, row.originalScale) end
        if row.originalPivot and same(pivot(row.widget), row.lastPivot) then call(row.widget, 'SetRenderTransformPivot', row.originalPivot) end
    end
    row.widget = nil; row.name = nil; row.last = nil; row.applied = false
end
local function discard(row)
    row.widget = nil; row.name = nil; row.last = nil; row.original = nil
    row.originalScale = nil; row.originalPivot = nil; row.lastScale = nil; row.lastPivot = nil; row.applied = false
end
local function findWidgets()
    local c = R.context
    local root = c and c.root
    if root and R.isLiveObject(root) then
        -- Fast tree search under root
        local stack = {{w = root, d = 0}}
        local seen = {}
        while #stack > 0 do
            local top = table.remove(stack)
            local cur, d = top.w, top.d
            if cur and d <= 8 then
                local addr = tostring(cur)
                if not seen[addr] then
                    seen[addr] = true
                    local n = full(cur) or ''
                    if n:match('%.LowestPriorityDynamicDrawCanvas$') then
                        S.widget = cur; S.name = n; S.canvas = n
                        S.original = translation(cur); S.originalScale = scale(cur); S.originalPivot = pivot(cur)
                        return
                    end
                    local cc = call(cur, 'GetChildrenCount') or 0
                    for i = 0, cc - 1 do
                        local ch = call(cur, 'GetChildAt', i)
                        if ch then stack[#stack+1] = {w = ch, d = d + 1} end
                    end
                    local wt = call(cur, 'get_property', 'WidgetTree')
                    if wt then
                        local rw = call(wt, 'get_property', 'RootWidget')
                        if rw then stack[#stack+1] = {w = rw, d = d + 1} end
                    end
                end
            end
        end
    end
end
host.sdk.callbacks.on_post_engine_tick(function()
    local c = R.context
    if not c.flight then discard(S); S.epoch = -1; return end
    if c.epoch ~= S.epoch then
        discard(S); S.epoch = c.epoch; S.attempts = 0; S.nextAttempt = 0; S.nextControls = 0
    end
    if R.tick >= S.nextControls then
        S.nextControls = R.tick + 60
        if S.controlCache == nil then
            S.controlCache = R.read('AC8_VR-OffscreenGroupControls.json') or R.read('ac8_offscreen_group_controls.json') or {}
        end
        local control = S.controlCache
        local x = tonumber(control.offsetX) or 0
        local factor = tonumber(control.scale) or .96
        if x ~= x or x < -3000 or x > 3000 then x = 0 end
        if factor ~= factor or factor < .5 or factor > 2 then factor = .96 end
        if control.enabled == false then x = 0; factor = 1 end
        if x ~= S.x or factor ~= S.scale then S.x = x; S.scale = factor; S.applied = false; S.attempts = 0; S.nextAttempt = 0 end
    end
    if S.applied then return end
    if S.attempts >= 8 or R.tick < (S.nextAttempt or 0) then return end
    S.attempts = S.attempts + 1; S.nextAttempt = R.tick + 30
    if not S.widget then findWidgets() end
    if not S.applied and S.widget and S.original and S.originalScale and S.originalPivot then
        local wanted = {X = S.original.X + S.x, Y = S.original.Y}
        local wantedScale = {X = S.originalScale.X * S.scale, Y = S.originalScale.Y * S.scale}
        local wantedPivot = {X = .5, Y = .5}
        call(S.widget, 'SetRenderTransformPivot', wantedPivot)
        if put(S.widget, wanted) and putScale(S.widget, wantedScale) and same(pivot(S.widget), wantedPivot) then
            S.last = wanted; S.lastScale = wantedScale; S.lastPivot = wantedPivot
            S.applied = true; S.writes = S.writes + 1
            S.status = 'off-screen canvas centered scale and left margin applied'
        else
            S.failures = S.failures + 1
            S.status = 'container setter readback failed'
        end
    end
end)
pcall(function() host.sdk.callbacks.on_script_reset(function() restore(S) end) end)
end

-- Accepted Bomb & Arrow Live Projection Controls
do
local R = AC8Runtime; local host = R.host('layout', 'accepted bomb projection')
local last
local lastArrowPacket
local arrowBaseCache
host.sdk.callbacks.on_post_engine_tick(function()
    if R.context.flight then
        R.gameplayCameraReadyEpoch = R.context.epoch
        R.gameplayCameraReady = true
    end
    local sw = R.customHUDConfig and R.customHUDConfig.specialWeapons
    local v = (sw and type(sw.bombFOV) == 'number') and sw.bombFOV or nil
    if not v then
        local cfg = R.bombLandingControlsCache or R.read('AC8_VR-BombLandingControls.json') or {}
        R.bombLandingControlsCache = cfg
        v = tonumber(cfg.fovAdjustmentDegrees) or 9
    end
    if v ~= v or v < -40 or v > 40 then v = 9 end
    local packet = '1|' .. tostring(v) .. '|0|' .. (R.context.flight and '1' or '0')
    if packet ~= last then
        uevr.api:dispatch_custom_event('AC8_BombProjectionControls', packet)
        last = packet
    end

    if not arrowBaseCache then
        arrowBaseCache = R.read('AC8_VR-ArrowLiveControls.json') or {commonX=0, commonY=0, targetX=0, targetY=0, noseX=0, noseY=0}
    end

    local he = R.customHUDConfig and R.customHUDConfig.hudElements
    local lcfg = he and he.ladder or {}
    local locCfg = he and he.locator or {}
    local noseCfg = he and he.nose or {}

    local userLocX = (tonumber(lcfg.x) or 0) + (tonumber(locCfg.x) or 0)
    local userLocY = (tonumber(lcfg.y) or 0) + (tonumber(locCfg.y) or 0)
    local userNoseX = (tonumber(lcfg.x) or 0) + (tonumber(noseCfg.x) or 0)
    local userNoseY = (tonumber(lcfg.y) or 0) + (tonumber(noseCfg.y) or 0)

    local canvasSize, _ = getCanvasVirtualSize()
    local safeH = math.min(canvasSize.Y, canvasSize.X * (9.0 / 16.0))
    local safeW = math.min(canvasSize.X, canvasSize.Y * (16.0 / 9.0))
    local marginX = math.max(0.0, (canvasSize.X - safeW) * 0.5)
    local marginY = math.max(0.0, (canvasSize.Y - safeH) * 0.5)

    -- In C++ AC8_ArrowLiveControls, commonX/commonY are baseline offsets.
    local commonX = tonumber(arrowBaseCache.commonX) or 0.0
    local commonY = tonumber(arrowBaseCache.commonY) or 0.0

    local baseLocX = -1232.0
    local baseLocY = -322.0
    local baseNoseX = -1232.0
    local baseNoseY = -322.0

    local nx = (tonumber(arrowBaseCache.noseX) or 0) + baseNoseX + marginX + userNoseX
    local ny = (tonumber(arrowBaseCache.noseY) or 0) - (baseNoseY + userNoseY)
    local tx = (tonumber(arrowBaseCache.targetX) or 0) + baseLocX + marginX + userLocX
    local ty = (tonumber(arrowBaseCache.targetY) or 0) - (baseLocY + userLocY)

    -- C++ AC8_ArrowLiveControls parser expects '%lf|%lf|%lf|%lf%c' matching exactly 4 items (nx, ny, tx, ty)
    local arrowPacket = string.format('%.1f|%.1f|%.1f|%.1f', commonX + nx, commonY + ny, commonX + tx, commonY + ty)
    if arrowPacket ~= lastArrowPacket then
        uevr.api:dispatch_custom_event('AC8_ArrowLiveControls', arrowPacket)
        lastArrowPacket = arrowPacket
    end
end)
host.sdk.callbacks.on_script_reset(function()
    uevr.api:dispatch_custom_event('AC8_BombProjectionControls', '0|0|0|0')
end)
end

-- Bomb Velocity Origin Anchor
do
local R = AC8Runtime; local host = R.host('layout', 'bomb velocity origin anchor')
local S = {version=73, epoch=-1, nextDiscover=0}; R.bombLineAnchor = S
local function call(o, k, ...)
    if o ~= uevr.api and not R.isLiveObject(o) then return end
    local ok, v = pcall(function(...) return o[k](o, ...) end, ...); if ok then return v end
end
local function field(o, k) local ok, v = pcall(function() return o[k] end); if ok then return v end end
local function xy(v)
    local x, y = field(v, 'X'), field(v, 'Y')
    if type(x) == 'number' and type(y) == 'number' and x == x and y == y and math.abs(x) < 1e7 and math.abs(y) < 1e7 then return {X=x, Y=y} end
end
local function disable(reason)
    if S.packet then uevr.api:dispatch_custom_event('AC8_BombLineAnchor', '0|0|0|0|0') end
    S.packet = nil; S.status = reason
end
local function discover()
    local root = R.context.root; if not R.isLiveObject(root) then return end
    local refs = R.hudLayoutRefs
    local icon = refs and refs.vicon
    local rootPath = (R.context.rootName or ''):match('^%S+ (.+)$')
    if not R.isLiveObject(icon) then
        local persistent = call(root, 'get_property', 'WBP_ChroniclePersistent')
        icon = call(persistent, 'get_property', 'VelocityIcon')
    end
    local iconName = call(icon, 'get_full_name') or ''
    if not R.isLiveObject(icon) or not rootPath or not iconName:find(' ' .. rootPath .. '.', 1, true) or not iconName:find('.WBP_ChroniclePersistent.', 1, true) then return end
    local bomb = call(root, 'get_property', 'WBP_ExplosivePredicationWidget')
    if not R.isLiveObject(bomb) then
        local cls = call(uevr.api, 'find_uobject', 'Class /Script/Live.LiveExplosivePredicationWidget')
        for i, o in ipairs(call(cls, 'get_objects_matching', false) or {}) do
            if i > 16 then break end
            if rootPath and (call(o, 'get_full_name') or ''):find(' ' .. rootPath .. '.', 1, true) and call(o, 'get_property', 'CachedLiveHUD') == R.context.hud then bomb = o; break end
        end
    end
    if call(bomb, 'get_property', 'CachedLiveHUD') ~= R.context.hud then return end
    local canvas = call(bomb, 'GetParent')
    if not R.isLiveObject(bomb) or not (call(canvas, 'get_full_name') or ''):match('^LiveDynamicDrawCanvas ') then return end
    S.icon = icon; S.iconName = iconName; S.bomb = bomb; S.canvas = canvas
    S.slate = call(call(uevr.api, 'find_uobject', 'Class /Script/UMG.SlateBlueprintLibrary'), 'get_class_default_object')
end
local function update()
    local c = R.context
    if S.epoch ~= c.epoch then disable('waiting for current HUD'); S.epoch = c.epoch; S.icon = nil; S.bomb = nil; S.canvas = nil; S.nextDiscover = 0 end
    if not c.flight then disable('outside flight'); return end
    if not R.isLiveObject(S.icon) or not R.isLiveObject(S.bomb) or not R.isLiveObject(S.canvas) or not R.isLiveObject(S.slate) then
        disable('waiting for velocity icon and bomb canvas')
        if R.tick < S.nextDiscover then return end; S.nextDiscover = R.tick + 60; discover()
    end
    if not R.isLiveObject(S.icon) or not R.isLiveObject(S.bomb) or not R.isLiveObject(S.canvas) then return end
    local ig = call(S.icon, 'GetPaintSpaceGeometry') or call(S.icon, 'GetCachedGeometry')
    local cg = call(S.canvas, 'GetPaintSpaceGeometry') or call(S.canvas, 'GetCachedGeometry')
    if not ig or not cg then disable('waiting for painted geometry'); return end
    local is = xy(call(S.slate, 'GetLocalSize', ig)); local cs = xy(call(S.slate, 'GetLocalSize', cg))
    if not is or not cs or is.X <= 0 or is.Y <= 0 or cs.X < 1000 or cs.Y < 500 then disable('waiting for painted geometry'); return end
    local absolute = xy(call(S.slate, 'LocalToAbsolute', ig, {X = is.X / 2, Y = is.Y / 2}))
    local target = absolute and xy(call(S.slate, 'AbsoluteToLocal', cg, absolute))
    local widget = call(S.bomb, 'get_address'); local canvas = call(S.canvas, 'get_address')
    if not target or type(widget) ~= 'number' or type(canvas) ~= 'number' then disable('invalid origin geometry'); return end
    if target.X < 0 or target.Y < 0 or target.X > cs.X or target.Y > cs.Y then disable('velocity icon outside canvas'); return end
    local packet = string.format('1|%.0f|%.0f|%.8f|%.8f', widget, canvas, target.X, target.Y)
    if packet ~= S.packet or R.tick - (S.sentAt or 0) >= 12 then
        uevr.api:dispatch_custom_event('AC8_BombLineAnchor', packet); S.packet = packet; S.sentAt = R.tick
    end
    S.status = 'top follows velocity icon every frame; lower endpoint and circle share calibrated projection'
    S.target = target; S.absoluteCenter = absolute; S.canvasSize = cs
end
host.sdk.callbacks.on_post_engine_tick(update)
host.sdk.callbacks.on_script_reset(function() disable('script reset'); uevr.api:dispatch_custom_event('AC8_BombProjectionControls', '0|0|0|0') end)
end

-- =========================================================================
-- AC8 Integrated HUD Layout & Display Engine
-- Unifies PitchLadder, Radar, AircraftInfo, Score, Locator, Whisky, DrawCanvas, Wingman
-- =========================================================================
do
local host = R.host('layout', 'integrated HUD positioning and presentation')
local cachedTargets = {}
local baseTransforms = {}

local function getBaseTransform(widget)
    if not widget or not R.isLiveObject(widget) then return nil end
    local n = R.objectCall(widget, 'get_full_name')
    if not n then return nil end
    if not baseTransforms[n] then
        local rt = R.objectCall(widget, 'get_property', 'RenderTransform')
        local t = rt and R.objectCall(rt, 'get_property', 'Translation')
        local sc = rt and R.objectCall(rt, 'get_property', 'Scale')
        local bx = (t and type(t.X) == 'number') and t.X or 0.0
        local by = (t and type(t.Y) == 'number') and t.Y or 0.0
        local bsc = (sc and type(sc.X) == 'number' and sc.X > 0.0) and sc.X or 1.0
        baseTransforms[n] = { x = bx, y = by, scale = bsc }
    end
    return baseTransforms[n]
end

local function findDescendantByName(root, name, maxDepth, exact)
    if not root or not R.isLiveObject(root) then return nil end
    maxDepth = maxDepth or 16
    local stack = { { w = root, d = 0 } }
    local seen = {}
    while #stack > 0 do
        local top = table.remove(stack)
        local cur = top.w
        local depth = top.d
        if cur and depth <= maxDepth then
            local addr = tostring(cur)
            if not seen[addr] then
                seen[addr] = true
                local fn = R.objectCall(cur, 'get_full_name') or ''
                local leaf = fn:match('%.([^%.]+)$')
                local hit = (leaf == name) or (not exact and fn:find(name, 1, true) ~= nil)
                if hit then return cur end
                local count = R.objectCall(cur, 'GetChildrenCount') or 0
                if type(count) == 'number' and count > 0 then
                    for i = 0, count - 1 do
                        local child = R.objectCall(cur, 'GetChildAt', i)
                        if child then table.insert(stack, { w = child, d = depth + 1 }) end
                    end
                end
                -- Also traverse UContentWidget (RetainerBox, SizeBox, Border) single child slot
                local content = R.objectCall(cur, 'GetContent')
                if content and R.isLiveObject(content) then
                    table.insert(stack, { w = content, d = depth + 1 })
                end
                local wt = R.objectCall(cur, 'get_property', 'WidgetTree')
                if wt then
                    local rootWidget = R.objectCall(wt, 'get_property', 'RootWidget')
                    if rootWidget then table.insert(stack, { w = rootWidget, d = depth + 1 }) end
                end
            end
        end
    end
    return nil
end

local function findAllDescendantsByNames(root, names, maxDepth)
    if not root or not R.isLiveObject(root) then return {} end
    maxDepth = maxDepth or 16
    local stack = { { w = root, d = 0 } }
    local seen = {}
    local results = {}
    local targetMap = {}
    for _, nm in ipairs(names) do targetMap[nm] = true end

    while #stack > 0 do
        local top = table.remove(stack)
        local cur = top.w
        local depth = top.d
        if cur and depth <= maxDepth then
            local addr = tostring(cur)
            if not seen[addr] then
                seen[addr] = true
                local fn = R.objectCall(cur, 'get_full_name') or ''
                for nm, _ in pairs(targetMap) do
                    if fn:find(nm, 1, true) then
                        table.insert(results, cur)
                        break
                    end
                end
                local count = R.objectCall(cur, 'GetChildrenCount') or 0
                if type(count) == 'number' and count > 0 then
                    for i = 0, count - 1 do
                        local child = R.objectCall(cur, 'GetChildAt', i)
                        if child then table.insert(stack, { w = child, d = depth + 1 }) end
                    end
                end
                -- Also traverse UContentWidget (RetainerBox, SizeBox, Border) single child slot
                local content = R.objectCall(cur, 'GetContent')
                if content and R.isLiveObject(content) then
                    table.insert(stack, { w = content, d = depth + 1 })
                end
                local wt = R.objectCall(cur, 'get_property', 'WidgetTree')
                if wt then
                    local rootWidget = R.objectCall(wt, 'get_property', 'RootWidget')
                    if rootWidget then table.insert(stack, { w = rootWidget, d = depth + 1 }) end
                end
            end
        end
    end
    return results
end

local function pruneNested(list)
    if not list or #list < 2 then return list or {} end
    local paths = {}
    for i, o in ipairs(list) do
        local ok, fn = pcall(function() return o:get_full_name() end)
        paths[i] = (ok and type(fn) == 'string') and (fn:match("^%S+%s+(.*)$") or fn) or tostring(o)
    end
    local keep = {}
    for i, o in ipairs(list) do
        local p = paths[i]
        local nested = false
        for j = 1, #paths do
            if j ~= i then
                local pj = paths[j]
                if #pj < #p and p:sub(1, #pj) == pj then
                    nested = true
                    break
                end
            end
        end
        if not nested then table.insert(keep, o) end
    end
    return keep
end

local function getWidgetTranslation(w)
    if not w or not R.isLiveObject(w) then return nil end
    local ok, t = pcall(function()
        local rt = w:get_property("RenderTransform")
        if rt and rt.Translation then
            local x = rt.Translation.X
            local y = rt.Translation.Y
            if type(x) == 'number' and type(y) == 'number' then
                return { X = x, Y = y }
            end
        end
        return nil
    end)
    return ok and t or nil
end

local baseTransformApplied = {}
local velIconPinned = false
local cachedRetainerBox = nil

local function redrawRetainer(widget)
    if not widget or not (R and R.isLiveObject and R.isLiveObject(widget)) then return end
    pcall(function() widget:InvalidateLayoutAndVolatility() end)
    if cachedRetainerBox and (R and R.isLiveObject and R.isLiveObject(cachedRetainerBox)) then
        pcall(function() cachedRetainerBox:RequestRender() end)
        return
    end
    local parent = R.objectCall(widget, 'GetParent')
    for _ = 1, 8 do
        if not parent or not (R and R.isLiveObject and R.isLiveObject(parent)) then break end
        local fn = R.objectCall(parent, 'get_full_name') or ''
        if fn:match('^RetainerBox ') or fn:match('BlurEffectBox') then
            cachedRetainerBox = parent
            pcall(function() parent:RequestRender() end)
            break
        end
        parent = R.objectCall(parent, 'GetParent')
    end
end

local function writeFpmStatus(integrated, tx, ty, sc)
    pcall(function()
        local f = io.open('data/ac8_fpm_status.txt', 'w')
        if f then
            f:write(string.format("version=0.1.0.76\nintegrated=%s\ntx=%.2f\nty=%.2f\nscale=%.2f\npinned=true\n",
                tostring(integrated), tx, ty, sc))
            f:close()
        end
    end)
end

local function applyElementDirect(widget, tx, ty, sc, op, applyPos)
    if not widget or not (R and R.isLiveObject and R.isLiveObject(widget)) then return end
    if applyPos ~= false and type(tx) == 'number' and type(ty) == 'number' then
        pcall(function() widget:SetRenderTranslation({ X = tx, Y = ty }) end)
    end
    local key = tostring(widget)
    local prev = baseTransformApplied[key]
    local needsScale = type(sc) == 'number' and sc > 0 and ((not prev) or math.abs((prev.sc or 1.0) - sc) > 0.001)
    local needsOp = type(op) == 'number' and ((not prev) or math.abs((prev.op or 1.0) - op) > 0.005)

    if needsScale then
        pcall(function() widget:SetRenderScale({ X = sc, Y = sc }) end)
    end
    if needsOp then
        pcall(function() widget:SetRenderOpacity(op) end)
    end

    if not prev then
        baseTransformApplied[key] = { sc = sc, op = op }
    else
        if needsScale then prev.sc = sc end
        if needsOp then prev.op = op end
    end
end
local function applyElementWithBase(widget, ox, oy, scaleFactor, opacity, applyPos)
    if not widget or not R.isLiveObject(widget) then return end
    local base = getBaseTransform(widget)
    if not base then return end
    local key = tostring(widget)
    local cur = baseTransformApplied[key]
    local final_x = base.x + (ox or 0.0)
    local final_y = base.y - (oy or 0.0)
    local final_scale = base.scale * (scaleFactor or 1.0)
    local final_op = opacity or 1.0

    local needsPos = applyPos ~= false and type(ox) == 'number' and type(oy) == 'number' and (not cur or math.abs(cur.x - final_x) > 0.05 or math.abs(cur.y - final_y) > 0.05)
    local needsScale = type(scaleFactor) == 'number' and scaleFactor > 0 and (not cur or math.abs(cur.sc - final_scale) > 0.001)
    local needsOp = type(opacity) == 'number' and (not cur or math.abs(cur.op - final_op) > 0.005)

    if needsPos or needsScale or needsOp then
        if needsPos then pcall(function() widget:SetRenderTranslation({ X = final_x, Y = final_y }) end) end
        if needsScale then pcall(function() widget:SetRenderScale({ X = final_scale, Y = final_scale }) end) end
        if needsOp then pcall(function() widget:SetRenderOpacity(final_op) end) end
        baseTransformApplied[key] = { x = final_x, y = final_y, sc = final_scale, op = final_op }
    end
end

local function simpleXY(v)
    if not v then return nil end
    local ok, x, y = pcall(function() return v.X, v.Y end)
    if ok and type(x) == 'number' and type(y) == 'number' and x == x and y == y then
        return { X = x, Y = y }
    end
    return nil
end

local velContainerLogged = false

local function resolveFlightWidgets(root, refs)
    local ladder = cachedTargets.ladder
    local whisky = cachedTargets.whisky
    local vel = cachedTargets.vel
    local vicon = cachedTargets.vicon

    if ladder and whisky and vel and vicon and
       R.isLiveObject(ladder) and R.isLiveObject(whisky) and R.isLiveObject(vel) and R.isLiveObject(vicon) then
        return ladder, whisky, vel, vicon
    end

    local cp = (refs and refs.cp and R.isLiveObject(refs.cp) and refs.cp)
    if not cp and root and R.isLiveObject(root) then
        cp = R.objectCall(root, 'get_property', 'WBP_ChroniclePersistent')
        if not cp or not R.isLiveObject(cp) then
            cp = findDescendantByName(root, 'ChroniclePersistent', 16, false)
        end
    end

    -- 1. Pitch Ladder (Altimeter)
    if not ladder or not R.isLiveObject(ladder) then
        ladder = (refs and refs.altimeter and R.isLiveObject(refs.altimeter) and refs.altimeter)
        if not ladder and cp and R.isLiveObject(cp) then
            ladder = R.objectCall(cp, 'get_property', 'Altimeter')
        end
        if not ladder and root and R.isLiveObject(root) then
            ladder = findDescendantByName(root, 'Altimeter', 16, true)
        end
        cachedTargets.ladder = ladder
    end

    if not cachedLadderBase and ladder and R.isLiveObject(ladder) then
        pcall(function()
            local slot = ladder:get_property('Slot')
            if slot then
                local pos = slot:GetPosition()
                if pos and type(pos.X) == 'number' and pos.X > 0 and type(pos.Y) == 'number' and pos.Y > 0 then
                    cachedLadderBase = { X = pos.X, Y = pos.Y }
                end
            end
        end)
    end

    -- 2. WhiskyMarkPanel
    if not whisky or not R.isLiveObject(whisky) then
        whisky = (refs and refs.whisky and R.isLiveObject(refs.whisky) and refs.whisky)
        if not whisky and cp and R.isLiveObject(cp) then
            whisky = R.objectCall(cp, 'get_property', 'WhiskyMarkPanel')
        end
        if not whisky and ladder and R.isLiveObject(ladder) then
            whisky = R.objectCall(ladder, 'get_property', 'WhiskyMarkPanel')
        end
        if not whisky and root and R.isLiveObject(root) then
            whisky = findDescendantByName(root, 'WhiskyMarkPanel', 16, true)
        end
        cachedTargets.whisky = whisky
    end

    -- 3. Velocity (Parent CanvasPanel container of VelocityIcon)
    if not vel or not R.isLiveObject(vel) then
        vel = (refs and refs.vel and R.isLiveObject(refs.vel) and refs.vel)
        if not vel and cp and R.isLiveObject(cp) then
            vel = R.objectCall(cp, 'get_property', 'Velocity') or find_desc(cp, 'Velocity', 12, true)
        end
        if not vel and root and R.isLiveObject(root) then
            vel = findDescendantByName(root, 'Velocity', 16, true)
        end
        if not vel then
            vel = findWidgetInChroniclePersistent('Velocity')
        end
        cachedTargets.vel = vel
    end

    -- 4. VelocityIcon (Flight Path Marker symbol)
    if not vicon or not R.isLiveObject(vicon) then
        vicon = (refs and refs.vicon and R.isLiveObject(refs.vicon) and refs.vicon)
        if not vicon and cp and R.isLiveObject(cp) then
            vicon = R.objectCall(cp, 'get_property', 'VelocityIcon') or find_desc(cp, 'VelocityIcon', 12, true)
        end
        if not vicon and root and R.isLiveObject(root) then
            vicon = findDescendantByName(root, 'VelocityIcon', 16, true)
        end
        if not vicon then
            vicon = findWidgetInChroniclePersistent('VelocityIcon')
        end
        cachedTargets.vicon = vicon
    end

    return ladder, whisky, vel, vicon
end

local function fpmCanvasLayout(o, parentSize)
    if not o or not R.isLiveObject(o) then return nil end
    local slot = nil
    pcall(function() slot = o:get_property('Slot') end)
    if not slot or not R.isLiveObject(slot) then return nil end
    local offsets, anchors, alignment = nil, nil, nil
    pcall(function()
        offsets = slot:GetOffsets()
        anchors = slot:GetAnchors()
        alignment = slot:GetAlignment()
    end)
    if not offsets or not anchors or not alignment then return nil end
    local left, top, right, bottom = offsets.Left, offsets.Top, offsets.Right, offsets.Bottom
    local minX, minY = anchors.Minimum and anchors.Minimum.X, anchors.Minimum and anchors.Minimum.Y
    local maxX, maxY = anchors.Maximum and anchors.Maximum.X, anchors.Maximum and anchors.Maximum.Y
    local alignX, alignY = alignment.X, alignment.Y
    if type(left) ~= 'number' or type(top) ~= 'number' or type(right) ~= 'number' or type(bottom) ~= 'number' or
       type(minX) ~= 'number' or type(minY) ~= 'number' or type(maxX) ~= 'number' or type(maxY) ~= 'number' or
       type(alignX) ~= 'number' or type(alignY) ~= 'number' then
        return nil
    end
    local stretchX = minX ~= maxX
    local stretchY = minY ~= maxY
    local width = stretchX and (parentSize.X * (maxX - minX) - left - right) or right
    local height = stretchY and (parentSize.Y * (maxY - minY) - top - bottom) or bottom
    if width <= 0 or height <= 0 then return nil end
    local pivot = { X = 0, Y = 0 }
    pcall(function()
        local p = o:get_property('RenderTransformPivot') or o:GetRenderTransformPivot()
        if p and type(p.X) == 'number' and type(p.Y) == 'number' then pivot = p end
    end)
    return {
        x = parentSize.X * minX + left - (stretchX and 0 or alignX * width),
        y = parentSize.Y * minY + top - (stretchY and 0 or alignY * height),
        w = width,
        h = height,
        px = pivot.X * width,
        py = pivot.Y * height
    }
end

local function computeFPMPose(velWidget, ladderWidget, defaultX, defaultY)
    if not velWidget or not R.isLiveObject(velWidget) or not ladderWidget or not R.isLiveObject(ladderWidget) then
        return defaultX, defaultY, false
    end
    local ok, resX, resY = pcall(function()
        local parentLadder = ladderWidget:GetParent()
        local parentVel = velWidget:GetParent()
        if not parentLadder or not parentVel then return nil, nil end
        local fnL = p(parentLadder) or ''
        local fnV = p(parentVel) or ''
        if fnL ~= fnV then return nil, nil end
        local slateLib = uevr and uevr.api and uevr.api:find_uobject('Class /Script/UMG.SlateBlueprintLibrary')
        if not slateLib then return nil, nil end
        local geom = parentLadder:GetCachedGeometry()
        if not geom then return nil, nil end
        local parentSize = slateLib:GetLocalSize(geom)
        if not parentSize or type(parentSize.X) ~= 'number' or parentSize.X <= 0 or type(parentSize.Y) ~= 'number' or parentSize.Y <= 0 then
            return nil, nil
        end
        local a = fpmCanvasLayout(ladderWidget, parentSize)
        local b = fpmCanvasLayout(velWidget, parentSize)
        if not a or not b then return nil, nil end
        local rt = ladderWidget:get_property('RenderTransform')
        if not rt or not rt.Translation or not rt.Scale then return nil, nil end
        local tx = rt.Translation.X or 0
        local ty = rt.Translation.Y or 0
        local sx = rt.Scale.X or 1.0
        local sy = rt.Scale.Y or 1.0
        if sx <= 0 or sy <= 0 then return nil, nil end
        local cx = a.x + tx + a.px + sx * (a.w * 0.5 - a.px)
        local cy = a.y + ty + a.py + sy * (a.h * 0.5 - a.py)
        local targetX = cx - b.x - b.px - sx * (b.w * 0.5 - b.px)
        local targetY = cy - b.y - b.py - sy * (b.h * 0.5 - b.py)
        return targetX, targetY
    end)
    if ok and type(resX) == 'number' and type(resY) == 'number' then
        return resX, resY, true
    end
    return defaultX, defaultY, false
end

local fpmDiagnosisDumped = false

local function simpleJsonString(val, indent)
    indent = indent or ""
    local subIndent = indent .. "  "
    local t = type(val)
    if t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local isArray = (#val > 0)
        local parts = {}
        if isArray then
            for _, v in ipairs(val) do
                table.insert(parts, subIndent .. simpleJsonString(v, subIndent))
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
        else
            for k, v in pairs(val) do
                table.insert(parts, subIndent .. string.format("%q: ", tostring(k)) .. simpleJsonString(v, subIndent))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        end
    else
        return "null"
    end
end

local function runFPMDiagnosis(ladderWidget, velContainer, velIcon, lp, appliedTx, appliedTy, linked)
    if fpmDiagnosisDumped then return end
    local R = rawget(_G, 'AC8Runtime')
    local tick = (R and R.tick) or 0
    if tick < 20 then return end

    local function serializeTransform(w)
        if not w or not (R and R.isLiveObject and R.isLiveObject(w)) then return nil end
        local ok, rt = pcall(function() return w:get_property('RenderTransform') end)
        if not ok or not rt then return nil end
        return {
            Translation = rt.Translation and { X = rt.Translation.X, Y = rt.Translation.Y },
            Scale = rt.Scale and { X = rt.Scale.X, Y = rt.Scale.Y },
            Angle = rt.Angle
        }
    end
    local function serializeSlot(w)
        if not w or not (R and R.isLiveObject and R.isLiveObject(w)) then return nil end
        local ok, s = pcall(function() return w:get_property('Slot') end)
        if not ok or not s then return nil end
        local pos, offsets = nil, nil
        pcall(function() pos = s:GetPosition() end)
        pcall(function() offsets = s:GetOffsets() end)
        return {
            name = p(s),
            position = pos and { X = pos.X, Y = pos.Y },
            offsets = offsets and { Left = offsets.Left, Top = offsets.Top, Right = offsets.Right, Bottom = offsets.Bottom }
        }
    end

    local inVpLadder, inVpVel, inVpIcon = false, false, false
    if ladderWidget and R and R.isLiveObject and R.isLiveObject(ladderWidget) then
        pcall(function() inVpLadder = ladderWidget:IsInViewport() end)
    end
    if velContainer and R and R.isLiveObject and R.isLiveObject(velContainer) then
        pcall(function() inVpVel = velContainer:IsInViewport() end)
    end
    if velIcon and R and R.isLiveObject and R.isLiveObject(velIcon) then
        pcall(function() inVpIcon = velIcon:IsInViewport() end)
    end

    local diag = {
        version = "0.1.0.71",
        tick = tick,
        canvasVirtualSize = cachedCanvasVirtualSize,
        canvasCenter = cachedCanvasCenter,
        ladder = {
            name = ladderWidget and p(ladderWidget) or "nil",
            parent = ladderWidget and p(ladderWidget:GetParent()) or "nil",
            inViewport = inVpLadder,
            transform = serializeTransform(ladderWidget),
            slot = serializeSlot(ladderWidget)
        },
        velocity = {
            name = velContainer and p(velContainer) or "nil",
            parent = velContainer and p(velContainer:GetParent()) or "nil",
            inViewport = inVpVel,
            transform = serializeTransform(velContainer),
            slot = serializeSlot(velContainer),
            applied = { tx = appliedTx, ty = appliedTy, linked = linked }
        },
        velocityIcon = {
            name = velIcon and p(velIcon) or "nil",
            parent = velIcon and p(velIcon:GetParent()) or "nil",
            inViewport = inVpIcon,
            transform = serializeTransform(velIcon),
            slot = serializeSlot(velIcon)
        }
    }

    local jsonStr = simpleJsonString(diag)
    local written = false

    -- Method 1: direct relative file write to data/
    local f1 = io.open('data/ac8_fpm_diagnosis.json', 'w')
    if f1 then
        f1:write(jsonStr)
        f1:close()
        written = true
    end

    -- Method 2: direct relative file write to root
    local f2 = io.open('ac8_fpm_diagnosis.json', 'w')
    if f2 then
        f2:write(jsonStr)
        f2:close()
        written = true
    end

    -- Method 3: realJSON dump
    if R and R.realJSON and R.realJSON.dump_file then
        pcall(function() R.realJSON.dump_file('ac8_fpm_diagnosis.json', diag, 2) end)
        written = true
    end

    if written then
        fpmDiagnosisDumped = true
        print(string.format('[AC8-VR] FPM Diagnosis successfully written at tick %d (linked=%s, tx=%.1f, ty=%.1f)', tick, tostring(linked), appliedTx or 0, appliedTy or 0))
    end
end

local cachedLayoutPlan = nil
local flightPlanComputed = false

local function recomputeLayoutPlan()
    local ctx = R.context
    if not ctx or not ctx.flight then return nil end
    local he = R.customHUDConfig and R.customHUDConfig.hudElements
    if not he then return nil end

    local canvasSize, canvasCenter = getCanvasVirtualSize()
    local safeW = math.min(canvasSize.X, canvasSize.Y * (16.0 / 9.0))
    local safeH = math.min(canvasSize.Y, canvasSize.X * (9.0 / 16.0))
    local marginX = math.max(0.0, (canvasSize.X - safeW) * 0.5)
    local marginY = math.max(0.0, (canvasSize.Y - safeH) * 0.5)

    local baseSafeX = (cachedLadderBase and cachedLadderBase.X) or (safeW * 0.1796875) -- 690.0 in 16:9
    local baseSafeY = (cachedLadderBase and cachedLadderBase.Y) or (safeH * 0.35)      -- 756.0 in 16:9
    local altBaseX = baseSafeX + marginX
    local altBaseY = baseSafeY + marginY

    local lcfg = he.ladder or {}
    local lx = tonumber(lcfg.x) or 0.0
    local ly = tonumber(lcfg.y) or 0.0
    local lsc = tonumber(lcfg.scale) or 1.0
    local lop = tonumber(lcfg.opacity) or 0.95

    local wcfg = he.whisky or {}
    local wx = tonumber(wcfg.x) or 0.0
    local wy = tonumber(wcfg.y) or 0.0
    local wsc = tonumber(wcfg.scale) or 1.0
    local wop = tonumber(wcfg.opacity) or 0.95

    local hcfg = he.heading or {}
    local hx = tonumber(hcfg.x) or 0.0
    local hy = tonumber(hcfg.y) or 0.0
    local hsc = tonumber(hcfg.scale) or 1.0
    local hop = tonumber(hcfg.opacity) or 0.95

    local rcfg = he.radar or {}
    local icfg = he.info or {}
    local scfg = he.score or {}
    local loccfg = he.locator or {}
    local wingcfg = he.wingman or {}
    local dcfg = he.drawcanvas or {}

    -- FPM (Flight Path Marker / Velocity) Mathematical Origin Alignment:
    -- Precomputed layout matching calibrated visual center across FHD and Ultrawide resolutions.
    -- Parent container offset (-1232.0, -322.0) with scale 0.75 perfectly counteracts the design baseline.
    -- Dynamic user offsets from ladder (lx, ly) and heading (hx, hy) are seamlessly integrated.
    cachedLayoutPlan = {
        ladder = { tx = altBaseX + lx, ty = altBaseY - ly, sc = lsc, op = lop },
        whisky = { tx = 0.0 + wx, ty = 0.0 - wy, sc = lsc * wsc, op = wop },
        velContainer = {
            tx = -1232.0 + lx + hx,
            ty = -322.0 - ly - hy,
            sc = 0.75,
            op = hop
        },
        velIcon = {
            tx = 1920.0,
            ty = 1087.0,
            sc = 1.0,
            op = hop
        },
        radar = { ox = tonumber(rcfg.x) or 0.0, oy = tonumber(rcfg.y) or 0.0, sc = tonumber(rcfg.scale) or 1.0, op = tonumber(rcfg.opacity) or 0.95 },
        info = { ox = tonumber(icfg.x) or 0.0, oy = tonumber(icfg.y) or 0.0, sc = tonumber(icfg.scale) or 1.0, op = tonumber(icfg.opacity) or 0.95 },
        score = { ox = tonumber(scfg.x) or 0.0, oy = tonumber(scfg.y) or 0.0, sc = tonumber(scfg.scale) or 1.0, op = tonumber(scfg.opacity) or 0.95 },
        locator = { op = tonumber(loccfg.opacity) or 0.95 },
        wingman = { ox = tonumber(wingcfg.x) or 0.0, oy = tonumber(wingcfg.y) or 0.0, sc = tonumber(wingcfg.scale) or 1.0, op = tonumber(wingcfg.opacity) or 0.95 },
        drawcanvas = { sc = tonumber(dcfg.scale) or 1.0, op = tonumber(dcfg.opacity) or 0.95 },
    }
    return cachedLayoutPlan
end

function R.invalidateHUDLayoutPlan()
    cachedLayoutPlan = nil
    flightPlanComputed = false
    baseTransformApplied = {}
    velIconPinned = false
    cachedRetainerBox = nil
    fpmDiagnosisDumped = false
end
R.recalculateHUDLayoutPlan = function()
    R.invalidateHUDLayoutPlan()
    return recomputeLayoutPlan()
end

function R.applyHUDLayoutIntegrated()
    local ctx = R.context
    if not ctx or not ctx.flight then
        flightPlanComputed = false
        return
    end
    R.gameplayCameraReadyEpoch = ctx.epoch
    R.gameplayCameraReady = true
    local refs = R.hudLayoutRefs or {}
    local root = refs.root or (ctx and ctx.root)
    local he = R.customHUDConfig and R.customHUDConfig.hudElements
    if not he then return end

    -- 1. Direct path resolution for flight widgets
    local ladderWidget, whiskyWidget, velContainer, velIcon = resolveFlightWidgets(root, refs)

    if not flightPlanComputed or not cachedLayoutPlan then
        cachedLayoutPlan = recomputeLayoutPlan()
        if cachedLayoutPlan and cachedCanvasVirtualSize then
            flightPlanComputed = true
        else
            if not cachedLayoutPlan then return end
        end
    end
    local lp = cachedLayoutPlan

    -- 1. PitchLadder (Altimeter) - Direct Memory Assignment
    if ladderWidget then
        applyElementDirect(ladderWidget, lp.ladder.tx, lp.ladder.ty, lp.ladder.sc, lp.ladder.op, true)
    end

    -- 1-1. WhiskyMarkPanel (Direct child of Altimeter) - Direct Memory Assignment
    if whiskyWidget and he.whisky then
        applyElementDirect(whiskyWidget, lp.whisky.tx, lp.whisky.ty, lp.whisky.sc, lp.whisky.op, true)
    end

    -- 1-2. Heading (Flight Path Marker / Velocity & VelocityIcon) - Precomputed & Integrated
    if he.heading and velContainer and R.isLiveObject(velContainer) then
        applyElementDirect(velContainer, lp.velContainer.tx, lp.velContainer.ty, lp.velContainer.sc, lp.velContainer.op, true)
        if not velIconPinned and velIcon and R.isLiveObject(velIcon) then
            pcall(function()
                velIcon:SetRenderTranslation({ X = lp.velIcon.tx, Y = lp.velIcon.ty })
                velIcon:SetRenderScale({ X = lp.velIcon.sc, Y = lp.velIcon.sc })
            end)
            velIconPinned = true
            redrawRetainer(velContainer)
            writeFpmStatus(true, lp.velContainer.tx, lp.velContainer.ty, lp.velContainer.sc)
        end
        if velIcon and R.isLiveObject(velIcon) then
            local key = tostring(velIcon)
            local prev = baseTransformApplied[key]
            if (not prev) or math.abs((prev.op or 1.0) - lp.velIcon.op) > 0.005 then
                pcall(function() velIcon:SetRenderOpacity(lp.velIcon.op) end)
                if not prev then baseTransformApplied[key] = { op = lp.velIcon.op } else prev.op = lp.velIcon.op end
            end
        end
    end

    -- 2. Radar (MiniMap, RadarCircle, Corners)
    if he.radar then
        local radarWidgets = cachedTargets.radarList
        if not radarWidgets or #radarWidgets == 0 or not R.isLiveObject(radarWidgets[1]) then
            local found = findAllDescendantsByNames(root, {
                'MiniMapLayer', 'MIniMapCanvas', 'RadarCircleCanvasPanel',
                'RadarCircleBase', 'MiniMapIconCanvasPanel', 'MiniMapCornerCanvas',
                'MiniMapSearchCorners', 'MiniMapEnlargedCorners'
            })
            if #found == 0 and refs.radar then table.insert(found, refs.radar) end
            radarWidgets = pruneNested(found)
            cachedTargets.radarList = radarWidgets
        end
        for _, rw in ipairs(radarWidgets) do
            applyElementWithBase(rw, lp.radar.ox, lp.radar.oy, lp.radar.sc, lp.radar.op, true)
        end
    end

    -- 3. AircraftInfo (WBP_PlayerStateWidget)
    local infoWidget = cachedTargets.info
    if not infoWidget or not R.isLiveObject(infoWidget) then
        infoWidget = findDescendantByName(root, 'WBP_PlayerStateWidget')
            or refs.info
            or findDescendantByName(root, 'PlaneCanvas')
        cachedTargets.info = infoWidget
    end
    if infoWidget and he.info then
        applyElementWithBase(infoWidget, lp.info.ox, lp.info.oy, lp.info.sc, lp.info.op, true)
    end

    -- 4. Score / MissionInfo (CampaignInfo container)
    local scoreWidget = refs.campaign or cachedTargets.score
    if not scoreWidget or not R.isLiveObject(scoreWidget) then
        scoreWidget = findDescendantByName(root, 'WBP_HUD_SubWidgets_Parts_CampaignInfo')
            or findDescendantByName(root, 'CampaignInfo')
            or refs.score
        cachedTargets.score = scoreWidget
    end
    if scoreWidget and he.score then
        applyElementWithBase(scoreWidget, lp.score.ox, lp.score.oy, lp.score.sc, lp.score.op, true)
    end

    -- 5. Locator (Opacity only)
    if he.locator then
        local locatorWidget = cachedTargets.locator
        if not locatorWidget or not R.isLiveObject(locatorWidget) then
            locatorWidget = findDescendantByName(root, 'WBP_LocatorWidget') or refs.locator
            cachedTargets.locator = locatorWidget
        end
        if locatorWidget and R.isLiveObject(locatorWidget) and type(lp.locator.op) == 'number' then
            pcall(function() locatorWidget:SetRenderOpacity(lp.locator.op) end)
        end
    end

    -- 6. Wingman (WBP_HUD_Command_Wingman)
    local wingmanWidget = cachedTargets.wingman
    if not wingmanWidget or not R.isLiveObject(wingmanWidget) then
        wingmanWidget = findDescendantByName(root, 'WBP_HUD_Command_Wingman')
            or findDescendantByName(root, 'Command_S')
            or refs.wingman
        cachedTargets.wingman = wingmanWidget
    end
    if wingmanWidget and he.wingman then
        applyElementWithBase(wingmanWidget, lp.wingman.ox, lp.wingman.oy, lp.wingman.sc, lp.wingman.op, true)
    end

    -- 7. Draw canvas (MainCanvas)
    local drawWidget = refs.maincv or cachedTargets.draw
    if not drawWidget or not R.isLiveObject(drawWidget) then
        drawWidget = findDescendantByName(root, 'MainCanvas')
        cachedTargets.draw = drawWidget
    end
    if drawWidget and he.drawcanvas then
        applyElementDirect(drawWidget, 0, 0, lp.drawcanvas.sc, lp.drawcanvas.op, false)
    end
end

R.applyAllHUDCustomPositions = R.applyHUDLayoutIntegrated

-- =========================================================================
-- Emergency: Force Show ALL HUD (4-frame dormant elements unlocker)
-- =========================================================================
local instantCycleActive = false
local instantCycleFrame = 0

function R.triggerInstantAwake()
    instantCycleActive = true
    instantCycleFrame = 0
    print('[AC8-VR] Emergency: Force Show ALL HUD triggered via Integrated Layout Engine...')
end

local function setAllHUDVisibilityCode(visCode)
    if not uevr or not uevr.api then return end
    local umg = uevr.api:find_uobject('Class /Script/UMG.Widget')
    if not umg then return end
    local ok, objs = pcall(function() return umg:get_objects_matching(false) end)
    if not ok or type(objs) ~= 'table' then return end
    for _, w in ipairs(objs) do
        local fn = R.objectCall(w, 'get_full_name') or ''
        if fn:find('/Engine/Transient', 1, true) and fn:find('MainFlight', 1, true) then
            pcall(function() w:SetVisibility(visCode) end)
        end
    end
end

local function updateInstantAwakeCycle()
    if not instantCycleActive then return end
    instantCycleFrame = instantCycleFrame + 1
    if instantCycleFrame == 1 then
        setAllHUDVisibilityCode(1) -- Collapse
    elseif instantCycleFrame >= 4 then
        setAllHUDVisibilityCode(4) -- SelfHitTestInvisible
        instantCycleActive = false
        instantCycleFrame = 0
        local ok, err = pcall(R.applyHUDLayoutIntegrated)
    if not ok and (R.tick or 0) % 180 == 0 then
        print('[AC8-VR] applyHUDLayoutIntegrated error: ' .. tostring(err))
    end
        print('[AC8-VR] Emergency: Force Show ALL HUD complete! All dormant elements awakened.')
    end
end

local lastLayoutEpoch = -1
local wasInFlight = false

host.sdk.callbacks.on_post_engine_tick(function()
    if instantCycleActive then updateInstantAwakeCycle() end
end)

uevr.sdk.callbacks.on_pre_viewport_client_draw(function(viewport_client, viewport)
    if viewport_client and (not R.isLiveObject or R.isLiveObject(viewport_client)) then
        pcall(function()
            local vs = viewport_client:get_property('ViewportSize')
            if vs and vs.X > 0 and vs.Y > 0 then
                local prevW = R.cachedViewportSize and R.cachedViewportSize.X or 0
                local prevH = R.cachedViewportSize and R.cachedViewportSize.Y or 0
                if prevW ~= vs.X or prevH ~= vs.Y then
                    R.cachedViewportSize = { X = vs.X, Y = vs.Y }
                    cachedCanvasVirtualSize = nil
                    cachedCanvasCenter = nil
                    cachedLayoutPlan = nil
                    flightPlanComputed = false
                    if R.syncLocatorConfigToDLL then pcall(R.syncLocatorConfigToDLL) end
                end
            end
        end)
    end

    local ctx = R.context
    if ctx and ctx.epoch and ctx.epoch ~= lastLayoutEpoch then
        lastLayoutEpoch = ctx.epoch
        velContainerLogged = false
        cachedTargets = {}
        baseTransforms = {}
        baseTransformApplied = {}
        cachedCanvasVirtualSize = nil
        cachedCanvasCenter = nil
        cachedLadderBase = nil
        cachedLayoutPlan = nil
        flightPlanComputed = false
        lastSizeCheckTick = -1000
        velIconPinned = false
        cachedRetainerBox = nil
    end

    -- Recalculate layout plan cleanly once when flight begins (e.g. after hangar/intro)
    if ctx and ctx.flight and not wasInFlight then
        wasInFlight = true
        cachedCanvasVirtualSize = nil
        cachedCanvasCenter = nil
        cachedLayoutPlan = nil
        flightPlanComputed = false
        baseTransformApplied = {}
        velIconPinned = false
        cachedRetainerBox = nil
        fpmDiagnosisDumped = false
    elseif ctx and not ctx.flight then
        wasInFlight = false
    end

    -- Apply HUD layout immediately prior to Slate viewport drawing
    if ctx and ctx.flight then
        local ok, err = pcall(R.applyHUDLayoutIntegrated)
        if not ok and (R.tick or 0) % 180 == 0 then
            print('[AC8-VR] applyHUDLayoutIntegrated error: ' .. tostring(err))
        end
    end
end)

host.sdk.callbacks.on_script_reset(function()
    velContainerLogged = false
    cachedTargets = {}
    baseTransforms = {}
    baseTransformApplied = {}
    cachedCanvasVirtualSize = nil
    cachedCanvasCenter = nil
    cachedLadderBase = nil
    cachedLayoutPlan = nil
    flightPlanComputed = false
    lastLayoutEpoch = -1
    instantCycleActive = false
    instantCycleFrame = 0
    fpmDiagnosisDumped = false
    velIconPinned = false
    cachedRetainerBox = nil
end)

rawset(_G, 'AC8_DumpFPMDiagnosis', function()
    fpmDiagnosisDumped = false
    local R = rawget(_G, 'AC8Runtime')
    if R and R.applyHUDLayoutIntegrated then
        pcall(R.applyHUDLayoutIntegrated)
    end
    print('[AC8-VR] Manual FPM Diagnosis triggered')
end)
end

end

-- Clean up legacy separate AC8_VelocityAlignment if present from previous reload
local oldAlign = rawget(_G, 'AC8_VelocityAlignment')
if oldAlign then
    oldAlign.stopped = true
    if oldAlign.restore then pcall(oldAlign.restore) end
    rawset(_G, 'AC8_VelocityAlignment', nil)
end

if registry.start then registry.start() end
