-- Community-derived flight HUD calibration and saved layout/effect controls.
-- Setup is deferred until HUDLayout enables it; changes use reflected widget setters.
-- Retain original transforms and refresh Slate after placement so geometry stays valid.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['inherited_hud'], 'Duplicate AC8 VR section: inherited_hud')
registry.sections['inherited_hud'] = function(R)

AC8Runtime.inheritedSetup[#AC8Runtime.inheritedSetup+1]=function()

do
-- Flat2VR Modding Community and Discord: inherited HUD layout. Discover flight canvases; preserve warning visibility, instrument anchors, radar placement, rigid cockpit camera and saved effect controls. Use reflected setters to notify Slate. Authored constants and calibration bounds are retained.
(function(uevr,json,print)


local CANVAS_X,  CANVAS_Y     = 1200, 350     
local TW_X,      TW_Y         = -35, -55      
local WHISKY_X,  WHISKY_Y     = 10, 6         
local VELOCITY_X, VELOCITY_Y  = -1227, -400   

local VELOCITY_NUDGE_X, VELOCITY_NUDGE_Y = 6, -46

local MAIN_X,    MAIN_Y       = 0, 0
local TACH_PULL, TACH_Y       = 0, 0
local RADAR_CIRCLE_DY         = -95           

local VICON_BASE_X,      VICON_BASE_Y      = 1920, 1087
local GUNRETICLE_BASE_X, GUNRETICLE_BASE_Y = 1920, 1080

local SHIFT_VIA_PERSISTENT = true
local FIX_RADAR_CIRCLE     = false
local SINGLE_INSTANCE      = true

local RESET_LIST = {
    { key = "GunReticle",           pat = "GunReticle",           x = 1920, y = 1080 },
    { key = "Seeker",               pat = "Seeker",               x = 0,    y = 0    },
    { key = "Locator",              pat = "Locator",              x = 0,    y = 0    },
    { key = "ExplosivePredication", pat = "ExplosivePredication", x = -TW_X, y = -TW_Y },
    { key = "TargetSelectionDraw",  pat = "TargetSelectionDraw",  x = 0,    y = 0    },
}

local DESIGN_DX, DESIGN_DY = 1294, -640

local ANCHOR_EXP_X, ANCHOR_EXP_Y = 494, 1746
local SCALE_TOL    = 400   
local K_MAX        = 2400  
local TOL_UNITS    = 3     
local CAL_GAIN0    = 0.5   
local CAL_MAX_ITER = 40
local CAL_FAIL_MAX = 120  
local CAL_STEP_EVERY  = 2    
local ASSERT_EVERY    = 20   
local VALIDATE_EVERY  = 180   
local MISSING_RETRY_EVERY = 1200  
local FINGERPRINT_EVERY   = 1200  
local HB_EVERY       = 600  
local MONITOR_EVERY  = 1800 
local SWEEP_RESIDUAL = true 
local SWEEP_THRESHOLD = 600 
local FORCE_K_X, FORCE_K_Y = 0, 0  

local TACH_K_TABLE = {
    { rx = 689,  ry = 630,  dx = 0,    dy = 0    },  
    { rx = 1026, ry = 938,  dx = -330, dy = -174 },  
    { rx = -330, ry = -174, dx = -330, dy = -174 },  
}
local TACH_K_TOL = 60          
local TACH_KX, TACH_KY = 0, 0  
local TACH_K_LOCKED = false    
local TACH_K_MATCH  = "AC8 layout"
local TACH_NUDGE_X, TACH_NUDGE_Y = 0, 0  

local K_FALLBACK = {
    { pat = "fa%-?18",        kx = 954,  ky = 570 },  
    { pat = "f%-?18",         kx = 954,  ky = 570 },
    { pat = "superhornet",    kx = 954,  ky = 570 },
    { pat = "hornet",         kx = 954,  ky = 570 },
    { pat = "fa%-?14",        kx = 0,    ky = 0   },  
    { pat = "f%-?14",         kx = 0,    ky = 0   },
    { pat = "tomcat",         kx = 0,    ky = 0   },
}

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
    if not AC8Runtime.isLiveObject(obj)then return nil,nil end
    if obj == nil then return nil, nil end
    local rt = get_field(obj, "RenderTransform")
    if rt == nil then return nil, nil end
    local t = get_field(rt, "Translation")
    if t == nil then return nil, nil end
    return get_field(t, "X"), get_field(t, "Y")
end

local function fast_rt(obj, tx, ty)
    if obj == nil then return false end
    pcall(function() obj:SetRenderTranslation({ X = tx, Y = ty }) end)
    return true
end

local function set_rt(obj, tx, ty, tag, quiet)
    if obj == nil then
        if not quiet then  end
        return false
    end
    pcall(function() obj:SetRenderTranslation({ X = tx, Y = ty }) end)
    return true
end
local function iter_children(w)
    local children = {}
    if w == nil then return children end
    local okc, cc = pcall(function() return w.GetChildrenCount and w:GetChildrenCount() or 0 end)
    if okc and type(cc) == "number" and cc > 0 then
        for i = 0, cc - 1 do
            local ok2, c = pcall(function() return w:GetChildAt(i) end)
            if ok2 and c then table.insert(children, c) end
        end
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
    if root == nil then return nil end
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

local function abs_center(w)
    if w == nil then return nil end
    for _, fn in ipairs({ "GetPaintSpaceGeometry", "GetCachedGeometry", "GetTickSpaceGeometry" }) do
        local ok, geo = pcall(function() return w[fn](w) end)
        if ok and geo ~= nil then
            local ap = get_field(geo, "AbsolutePosition")
            local sz = get_field(geo, "Size")
            local ax, ay = get_field(ap, "X"), get_field(ap, "Y")
            local sx, sy = get_field(sz, "X"), get_field(sz, "Y")
            if type(ax) == "number" and type(ay) == "number"
               and type(sx) == "number" and type(sy) == "number" and sx > 0 and sy > 0 then
                return { x = ax + sx / 2, y = ay + sy / 2, via = fn }
            end
        end
    end
    return nil
end

local function pawn_full_name()
    if uevr == nil or uevr.api == nil or uevr.api.get_player_pawn == nil then return nil end
    local ok, pawn = pcall(function() return uevr.api:get_player_pawn() end)
    if not ok or pawn == nil then return nil end
    local ok2, nm = pcall(function() return pawn:get_full_name() end)
    if ok2 and type(nm) == "string" then return nm end
    return nil
end
local function fallback_k(name)
    if name == nil then return nil end
    local low = string.lower(name)
    for _, it in ipairs(K_FALLBACK) do
        if low:find(it.pat) then return it.kx, it.ky end
    end
    return nil
end

local C = {
    ready  = false,
    keep   = nil, base = nil, wtsc = nil, maincv = nil, cp = nil,
    ts = nil, ta = nil, vicon = nil, vel = nil, whisky = nil,
    radar = {}, radar_main = nil,
    pins = {},          
}
local cal = {
    active = false, kx = 0, ky = 0, gain = CAL_GAIN0, iter = 0,
    scale = nil, pex = nil, pey = nil, cur_fp = nil, warm = 0, fail = 0,
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
                        if not quiet then
                            
                        end
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
    if not quiet then
        if fixed > 0 then
            
        else
            
        end
        if C.prof ~= nil then
            for _, prof in ipairs(C.prof) do
                
                if prof.max_layer ~= nil then
                    
                end
            end
            
        end
    end
    return fixed
end

local function match_tach_k()
    if TACH_K_LOCKED then
        TACH_K_MATCH = string.format("AC8 layout value=%d, value=%d", TACH_KX, TACH_KY)
        return
    end
    local r = C.resid
    if r == nil then
        TACH_KX, TACH_KY = 0, 0
        TACH_K_MATCH = "AC8 layout"
        return
    end
    for _, e in ipairs(TACH_K_TABLE) do
        if math.abs(r.x - e.rx) <= TACH_K_TOL and math.abs(r.y - e.ry) <= TACH_K_TOL then
            TACH_KX, TACH_KY = e.dx, e.dy
            TACH_K_MATCH = string.format("AC8 layout value=%.0f, value=%.0f, value=%d, value=%d", r.x, r.y, TACH_KX, TACH_KY)
            if TACH_KX ~= 0 or TACH_KY ~= 0 then TACH_K_LOCKED = true end
            return
        end
    end
    TACH_KX, TACH_KY = 0, 0
    TACH_K_MATCH = string.format("AC8 layout value=%.0f, value=%.0f", r.x, r.y)
end

local PROF_DRIFT_TOL = 300
local function monitor_profiles()
    if C.cp == nil or C.prof == nil then return end
    local now = capture_profiles(false, true)
    if #now == 0 then return end
    local drift = false
    for i = 1, math.min(#now, #C.prof) do
        local a, b = C.prof[i], now[i]
        local dx = math.abs((b.sx or 0) - (a.sx or 0))
        local dy = math.abs((b.sy or 0) - (a.sy or 0))
        if dx > PROF_DRIFT_TOL or dy > PROF_DRIFT_TOL then drift = true end
    end
    C.prof = now  
    if drift then
        
    end
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
    local n = 0
    for _, pin in ipairs(C.pins) do
        if pin.obj ~= nil and (slow or not pin.slow) then
            local x, y = pin.x, pin.y
            if pin.dyn then x = R0_X + cal.kx; y = R0_Y + cal.ky end
            if pin.tag == "WhiskyMarkPanel(W)" and AC8Runtime and AC8Runtime.customHUDConfig and AC8Runtime.customHUDConfig.hudElements and AC8Runtime.customHUDConfig.hudElements.whisky then
                local we = AC8Runtime.customHUDConfig.hudElements.whisky
                x = x + (we.x or 0.0)
                y = y + (we.y or 0.0)
                if we.scale then pcall(function() pin.obj:SetRenderScale({ X = we.scale, Y = we.scale }) end) end
                if we.opacity then pcall(function() pin.obj:SetRenderOpacity(we.opacity) end) end
            end
            local cx, cy = get_rt_xy(pin.obj)
            local okx = (type(cx) == "number" and math.abs(cx - x) < 1)
            local oky = (type(cy) == "number" and math.abs(cy - y) < 1)
            if not (okx and oky) then
                fast_rt(pin.obj, x, y)
            end
            n = n + 1
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
        if C.keep ~= nil then
            pcall(function() C.keep.RenderOpacity = 1.0 end)
            pcall(function() C.keep.Visibility = 0 end)
        end
        if C.base ~= nil then
            pcall(function() C.base.RenderOpacity = 1.0 end)
            pcall(function() C.base.Visibility = 0 end)
        end
    end
    if AC8Runtime and AC8Runtime.applyAllHUDCustomPositions then
        pcall(AC8Runtime.applyAllHUDCustomPositions)
    end
    return n
end

local function cal_use_fallback(why, name)
    local kx, ky = fallback_k(name)
    if kx == nil then kx = 0; ky = 0 end
    cal.kx, cal.ky = kx, ky
    cal.active = false
    
    assert_pins(true)   
    return true
end

local function cal_step()
    if not cal.active then return true end
    
    if cal.warm > 0 then
        cal.warm = cal.warm - 1
        return false
    end
    if FORCE_K_X ~= 0 or FORCE_K_Y ~= 0 then
        cal.kx, cal.ky = FORCE_K_X, FORCE_K_Y
        cal.active = false
        
        assert_pins(true)   
        return true
    end
    if C.ts == nil or C.ta == nil or C.radar_main == nil then
        return cal_use_fallback("AC8 layout", cal.cur_fp)
    end
    local a  = abs_center(C.ts)
    local b  = abs_center(C.ta)
    local an = abs_center(C.radar_main)
    if a == nil or b == nil or an == nil then

        cal.fail = cal.fail + 1
        if cal.fail == 1 then
            
        end
        if cal.fail >= CAL_FAIL_MAX then
            cal.active = false
            
        end
        return false
    end
    cal.fail = 0
    
    if cal.scale == nil then
        if math.abs(an.x - ANCHOR_EXP_X) <= SCALE_TOL and math.abs(an.y - ANCHOR_EXP_Y) <= SCALE_TOL then
            cal.scale = 1
        elseif math.abs(an.x - ANCHOR_EXP_X / 2) <= SCALE_TOL / 2
           and math.abs(an.y - ANCHOR_EXP_Y / 2) <= SCALE_TOL / 2 then
            cal.scale = 2   
        else
            
            return cal_use_fallback("AC8 layout", cal.cur_fp)
        end
        
    end
    local s = cal.scale
    local mx = (a.x + b.x) / 2 * s
    local my = (a.y + b.y) / 2 * s
    local ax = an.x * s
    local ay = an.y * s
    local ex = (mx - ax) - DESIGN_DX
    local ey = (my - ay) - DESIGN_DY

    if math.abs(ex) < TOL_UNITS and math.abs(ey) < TOL_UNITS then
        cal.active = false
        
        return true
    end
    if math.abs(cal.kx) > K_MAX or math.abs(cal.ky) > K_MAX then
        return cal_use_fallback("AC8 layout", cal.cur_fp)
    end
    cal.iter = cal.iter + 1
    if cal.iter > CAL_MAX_ITER then
        return cal_use_fallback("AC8 layout", cal.cur_fp)
    end
    
    if cal.pex ~= nil and cal.pey ~= nil then
        local pe = math.max(math.abs(cal.pex), math.abs(cal.pey))
        local ne = math.max(math.abs(ex), math.abs(ey))
        if ne > pe * 1.05 and cal.gain > 0.06 then
            cal.gain = cal.gain / 2
            
        end
    end
    cal.kx = cal.kx - cal.gain * ex
    cal.ky = cal.ky - cal.gain * ey
    cal.pex, cal.pey = ex, ey
    assert_pins(true)   
    
    return false
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

local effect_originals={}
local effect_clear=true
local effect_retain=false
local effect_bright_ladder=false
local effect_bright_weapons=false
local effect_bright_all=false
local effect_text_originals={}
local effect_text_rows={}
local function effect_material_name(material)
    if material==nil then return "None" end
    local ok,name=pcall(function() return material:get_full_name() end)
    return ok and name or "Material reference unavailable"
end
local function effect_poll()
    local ok,cmd=pcall(function() return json.load_file("ac8_workshop_effect_controls.json") end)
    if ok and type(cmd)=="table" and type(cmd.clearMaterial)=="boolean" then effect_clear=cmd.clearMaterial end
    if ok and type(cmd)=="table" then
        if type(cmd.retainRendering)=="boolean" then effect_retain=cmd.retainRendering end
        if type(cmd.brightLadder)=="boolean" then effect_bright_ladder=cmd.brightLadder end
        if type(cmd.brightWeapons)=="boolean" then effect_bright_weapons=cmd.brightWeapons end
        if type(cmd.brightAllPanels)=="boolean" then effect_bright_all=cmd.brightAllPanels end
    end
end
local function effect_text_apply()
    local root=C.keep
    if not root then effect_text_rows={};return end
    local prefix=root:get_full_name():match("%s(.+)$")
    if not prefix then return end
    if not effect_bright_ladder and not effect_bright_weapons and not effect_bright_all and not next(effect_text_originals) then
        effect_text_rows={};return
    end
    local cls=uevr.api:find_uobject("Class /Script/UMG.Widget")
    if not cls then return end
    local rows={}
    for _,o in ipairs(cls:get_objects_matching(false) or {}) do
        local ok,err=pcall(function()
            local full=o:get_full_name();local path=full:match("%s(.+)$")
            if not path or path:sub(1,#prefix+1)~=prefix.."." then return end
            local leaf=path:match("([^.]+)$")
            local group=nil

            if path:find(".WBP_ChroniclePersistent.",1,true) or leaf=="WBP_ChroniclePersistent" then group="ladder"
            elseif path:find("PlayerState",1,true) then group="weapons"
            elseif path:lower():find("minimap",1,true) then group="radar"
            elseif path:find("CampaignInfo",1,true) then group="score-timer"
            elseif path:find(".HUDMessageWidget.",1,true) or leaf=="HUDMessageWidget" then group="comms-messages" end
            if not group then return end
            local enabled=effect_bright_all or (group=="ladder" and effect_bright_ladder) or (group=="weapons" and effect_bright_weapons)
            local base=effect_text_originals[full]
            if not enabled and not base then return end
            if not base then
                local opacity=o:GetRenderOpacity()
                assert(type(opacity)=="number","Original widget opacity unavailable")
                base={opacity=opacity};effect_text_originals[full]=base
            end
            local wanted=enabled and 1.0 or base.opacity
            if math.abs(o:GetRenderOpacity()-wanted)>0.001 then o:SetRenderOpacity(wanted) end
            local actual=o:GetRenderOpacity()
            rows[#rows+1]={name=leaf,path=path,group=group,original=base.opacity,current=actual,
                enabled=enabled,verified=math.abs(actual-wanted)<0.001}
            if not enabled then effect_text_originals[full]=nil end
        end)
        if not ok then rows[#rows+1]={error=tostring(err),verified=false} end
    end
    effect_text_rows=rows
end
local function effect_apply(blur)
    if not blur then return end
    local name=blur:get_full_name()
    local base=effect_originals[name]
    if not base then
        local ok,material=pcall(function() return blur:get_property("EffectMaterial") end)
        assert(ok,"Original effect material could not be read")
        local retain=blur:get_property("bRetainRender")
        assert(type(retain)=="boolean","Original retainer flag unavailable")
        base={material=material,retain=retain};effect_originals[name]=base
    end
    local wanted=nil
    if not effect_clear then wanted=base.material end
    local current=blur:get_property("EffectMaterial")
    if current~=wanted then blur:SetEffectMaterial(wanted) end
    local retainWanted=base.retain
    if effect_retain then retainWanted=true end
    if blur:get_property("bRetainRender")~=retainWanted then
        blur:SetRetainRendering(retainWanted)
        pcall(function() blur:RequestRender() end)
    end
    local actual=blur:get_property("EffectMaterial")
    local desiredName=effect_material_name(wanted)
    local actualName=effect_material_name(actual)
    local actualRetain=blur:get_property("bRetainRender")
    
end
effect_poll()

local refresh_remaining=0
local refresh_reason='startup'
local function queue_hud_refresh(reason)
    refresh_remaining=2
    refresh_reason=reason
end
local function refresh_hud_layout()
    if not C.ready or refresh_remaining<=0 then return end
    assert_pins(true)
    local invalidated=pcall(function() C.keep:InvalidateLayoutAndVolatility() end)
    local prepass=pcall(function() C.keep:ForceLayoutPrepass() end)
    local rendered=false
    if C.workshopBlur then rendered=pcall(function() C.workshopBlur:RequestRender() end) end
    refresh_remaining=refresh_remaining-1
    
end
uevr.sdk.callbacks.on_lua_event(function(name,data)
    if name=='AC8_HUD_Refresh' then queue_hud_refresh(data or 'glow_activation') end
end)

-- Bind the current flight HUD and its anchors. Retry with bounded backoff
-- after HUD replacement; never treat an old widget name as lifetime proof.
local function discover()
    
    
    C.keep = nil; C.base = nil; C.wtsc = nil; C.maincv = nil; C.cp = nil
    C.ts = nil; C.ta = nil; C.vicon = nil; C.vel = nil; C.whisky = nil; C.altimeter = nil; C.campaign = nil
    C.radar = {}; C.radar_main = nil; C.pins = {}
    C.resid = nil; C.prof = nil

    local uw = all_userwidgets()
    
    local mfs = all_mainflights(uw)
    
    if #mfs == 0 then
        
        return false
    end
    local keep, keep_addr = nil, nil
    for _, mf in ipairs(mfs) do
        local inv = nil
        pcall(function() inv = mf:IsInViewport() end)
        if inv == true then keep = mf; keep_addr = tostring(mf); break end
    end
    if AC8Runtime.context.rootName:match('^WBP_HUD_Chronicle_MainFlight') then
        keep = AC8Runtime.context.root
        keep_addr = tostring(keep)
        pcall(function()
            if not keep:IsInViewport() then keep:AddToViewport() end
        end)
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
    C.keep = keep

    pcall(function() keep.RenderOpacity = 1.0 end)
    pcall(function() keep:SetRenderOpacity(1.0) end)
    pcall(function() keep.Visibility = 0 end)
    pcall(function() keep:SetVisibility(0) end)

    local base = find_desc(keep, "BaseCanvas", 6, true)
    if base == nil then
        
        return false
    end
    C.base = base
    pcall(function() base.RenderOpacity = 1.0 end)
    pcall(function() base.Visibility = 0 end)

    local blur = find_desc(base, "BlurEffectBox", 8)
    if blur then
        C.workshopBlur=blur
        pcall(effect_apply,blur)
        pcall(function() blur.Visibility = 0 end)
        pcall(function() blur.RenderOpacity = 1.0 end)
    end

    local wtsc = find_desc(base, "WorldToScreenDrawCanvas", 3, true)
    if wtsc == nil then
        
        return false
    end
    C.wtsc = wtsc
    C.maincv = find_desc(base, "MainCanvas", 3, true)
    C.cp = find_desc(wtsc, "ChroniclePersistent", 3)
    C.vicon  = find_desc(wtsc, "VelocityIcon", 12, true)
    C.vel    = find_desc(wtsc, "Velocity", 12, true)
    C.altimeter = find_desc(wtsc, "Altimeter", 12, true)
    C.whisky = find_desc(wtsc, "WhiskyMarkPanel", 12, true)
    C.ts     = find_desc(wtsc, "SpeedTachometerCenterPanel", 14, true)
    C.ta     = find_desc(wtsc, "AltitudeTachometerCenterPanel", 14, true)
    C.campaign = find_desc(C.keep, "CampaignInfo", 14, false)
    C.info     = find_desc(C.keep, "WBP_PlayerStateWidget", 14, false) or find_desc(C.keep, "PlaneCanvas", 14, false) or find_desc(C.keep, "PlayerStatus", 14, false)
    C.radar  = collect_radar(C.maincv)
    if #C.radar > 0 then
        
        for _, w in ipairs(C.radar) do
            local v = get_field(w, "Visibility")
            if v == nil or v == 0 or v == 3 or v == 4 then C.radar_main = w; break end
        end
        if C.radar_main == nil then C.radar_main = C.radar[1] end
    end
    AC8Runtime.hudLayoutRefs={
        radar=C.radar_main,
        root=C.keep,
        wtsc=C.wtsc,
        info=C.info,
        score=C.campaign,
        maincv=C.maincv,
        cp=C.cp,
        vicon=C.vicon,
        vel=C.vel,
        altimeter=C.altimeter,
        whisky=C.whisky,
        ts=C.ts,
        ta=C.ta,
        campaign=C.campaign,
        radarList=C.radar,
        epoch=C.hudEpoch
    }

    sweep_residual(false)
    match_tach_k()
    

    table.insert(C.pins, { obj = C.wtsc,   x = TW_X, y = TW_Y, tag = "AC8 layout" })
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
        set_rt(C.cp, R0_X + cal.kx, R0_Y + cal.ky, "AC8 layout", false)
    else
        
        table.insert(C.pins, { obj = C.wtsc, x = CANVAS_X, y = CANVAS_Y, tag = "AC8 layout" })
        
    end
    if FIX_RADAR_CIRCLE then
        for _, w in ipairs(C.radar) do
            set_rt(w, 0, RADAR_CIRCLE_DY, "RADARCIRCLE:" .. short_name(w), false)
        end
        
    end
    pcall(function() wtsc.Visibility = 0 end)
    pcall(function() wtsc.RenderOpacity = 1.0 end)
    if C.maincv ~= nil then
        pcall(function() C.maincv.Visibility = 0 end)
        pcall(function() C.maincv.RenderOpacity = 1.0 end)
    end

    
    cal.kx, cal.ky = 0, 0
    local fkx, fky = fallback_k(cal.cur_fp)
    if fkx ~= nil then
        cal.kx, cal.ky = fkx, fky
        
    end
    cal.gain = CAL_GAIN0; cal.iter = 0; cal.scale = nil; cal.pex = nil; cal.pey = nil
    cal.warm = 3
    cal.active = true
    assert_pins(true)   

    C.ready = true
    queue_hud_refresh("initial_layout")
    
    return true
end

-- Expose HUD layout rediscovery globally and via AC8Runtime
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
            local ok, v = pcall(function() return e:get_full_name() end)
            if not ok or v == nil or v == "<no full_name>" then
                
                C.ready = false
                return false
            end
        end
    end
    return true
end

local function fingerprint_check()
    local nm = pawn_full_name()
    if nm == nil then return end
    if cal.cur_fp == nil then
        cal.cur_fp = nm
        
        return
    end
    if nm ~= cal.cur_fp then
        
        cal.cur_fp = nm
        cal.kx, cal.ky = 0, 0
        local fkx, fky = fallback_k(nm)
        if fkx ~= nil then cal.kx, cal.ky = fkx, fky end
        cal.gain = CAL_GAIN0; cal.iter = 0; cal.scale = nil; cal.pex = nil; cal.pey = nil
        cal.warm = 3
        cal.active = true
        assert_pins()
    end
end

local CAM_ANIM_KILL = true     
local CAM_KILL_EVERY = 1      
local cam_kill_oklog  = false  
local cam_kill_faillog = false 
local cam_kill_path   = ""     
local function cam_get_pawn()
    local ok, p = pcall(function() return uevr.api:get_local_pawn(0) end)
    if ok and p ~= nil then return p end
    local ok2, p2 = pcall(function() return uevr.api:get_player_pawn() end)
    if ok2 and p2 ~= nil then return p2 end
    return nil
end

-- Flight comfort: stop authored camera shake/animation. The caller yields
-- while cinematic presentation owns the camera so authored shots can play.
local function cam_kill_anims()
    local pm = nil
    pcall(function()
        local a = uevr and uevr.api
        if a == nil then return end
        local ctrl = nil
        local pawn = cam_get_pawn()
        if pawn ~= nil then
            pcall(function() ctrl = pawn.Controller end)
            if ctrl == nil then
                pcall(function() ctrl = pawn:get_Controller() end)
                if ctrl ~= nil then cam_kill_path = "pawn:get_Controller" end
            else
                cam_kill_path = "pawn.Controller"
            end
        end
        if ctrl == nil then
            pcall(function()
                if a.get_player_controller ~= nil then ctrl = a:get_player_controller() end
            end)
            if ctrl ~= nil then cam_kill_path = "api:get_player_controller" end
        end
        if ctrl == nil then return end
        pcall(function() pm = ctrl.PlayerCameraManager end)
        if pm == nil then pcall(function() pm = ctrl:get_PlayerCameraManager() end) end
    end)
    if pm == nil then return false end

    pcall(function() pm:StopAllCameraAnims(true) end)
    pcall(function() pm:StopAllCameraShakes(true) end)
    return true
end

local frame_n = 0
local retry_gap = 10      
-- The epoch invalidates cached HUD objects. Frequent work enforces cached
-- transforms; expensive calibration/discovery has separate cadences below.
local function on_frame()
    local intent=rawget(_G,'AC8_CinematicIntent')
    if intent then intent.hudAcknowledged=true end
    local context=AC8Runtime.context
    if C.hudEpoch~=context.epoch then C.hudEpoch=context.epoch;C.ready=false;retry_gap=10;frame_n=0 end
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
    if cal.active and (frame_n % CAL_STEP_EVERY == 0) then
        cal_step()
        if not cal.active then queue_hud_refresh("layout_settled") end
    end
    if frame_n % 8 == 0 then refresh_hud_layout() end
    if frame_n % ASSERT_EVERY == 0 then assert_pins() end          
    if frame_n % VALIDATE_EVERY == 0 then if not validate() then return end end
    if frame_n % FINGERPRINT_EVERY == 0 then fingerprint_check() end
    if frame_n % MISSING_RETRY_EVERY == 0 then retry_missing() end
    if frame_n % MONITOR_EVERY == 0 then monitor_profiles() end   
    if frame_n % HB_EVERY == 0 then
        assert_pins(true)   
        
    end
    
    if CAM_ANIM_KILL and not (intent and intent.active) and frame_n % CAM_KILL_EVERY == 0 then
        local okp = cam_kill_anims()
        if okp and not cam_kill_oklog then
            cam_kill_oklog = true
            
        elseif not okp and not cam_kill_faillog then
            cam_kill_faillog = true
            
        end
    end
end

local ok0, err0 = pcall(discover)
if not ok0 then  end

local function register_tick()
    local cbs = uevr and uevr.sdk and uevr.sdk.callbacks
    if cbs and cbs.on_post_engine_tick then
        local ok2, e2 = pcall(function() cbs.on_post_engine_tick(on_frame) end)
        if ok2 then  return true end
        
    end
    return false
end
local okr, errr = pcall(register_tick)
if not okr then  end

end)(AC8Runtime.host('layout','ac8_hud_inspect.lua'),AC8Runtime.json,AC8Runtime.log)
end
end

AC8Runtime.inheritedSetup[#AC8Runtime.inheritedSetup+1]=function()

do
-- Flat2VR Modding Community and Discord: inherited ac8_ladder_fix_v19_fast, including the original groups described as Herbert's in the supplied code. Preserve ladder, radar, aircraft and canvas controls and numeric originals; apply saved workshop revisions. HUD update ordering is owned by ac8_20_hud_layout.lua.
(function(uevr,json,print)


local api = uevr.api
if api == nil then return end

local SCRIPT_VERSION = "v19"

local TARGETS = {
    {
        key    = "ladder",
        label  = "PitchLadder",
        from   = { "PitchMeter" },         
        nodes  = {
            "Altimeter",      

        },

        sublabel = "Heading",
        x = 690.0, y = 756.0, active = true,  op = 1.0, sc = 1.0,
        
        sdx = -1913.0, sdy = -1200.0,
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
        x = 0.0, y = 0.0, active = false, op = 1.0, sc = 1.0,
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
        x = 0.0, y = 0.0, active = false, op = 1.0, sc = 1.0,
    },
    {

        key    = "drawcanvas",
        label  = "Draw canvas",
        from   = { "WorldToScreen", "DynamicDraw" },
        nodes  = {
            "LowestPriorityDynamicDrawCanvas",
            "LowestPriorityCanvasWorldToScreenDraw",
            "WorldToScreenDrawCanvas",
            "TopPriorityCanvas",
            "MainCanvas",
            "DynamicDrawCanvas",
        },
        nopos = true,
        x = 0.0, y = 0.0, active = false, op = 1.0, sc = 1.0,
    },
}

local SCOPE = "WBP_HUD_Chronicle_MainFlight"

local DEFAULTS = {}
for _, t in ipairs(TARGETS) do
    DEFAULTS[t.key] = { x = t.x, y = t.y, active = t.active, op = t.op, sc = t.sc,
                        sdx = t.sdx or 0.0, sdy = t.sdy or 0.0 }
end

local RESCAN_EVERY = 1800

local CFG_FILE = "ac8_ladder.json"
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

local function path_of(o)
    local s = full_name(o)
    if s == nil then return nil end
    return s:match("^%S+%s+(.*)$") or s
end

local function num_field(o, names)
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return o[n] end)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

local function get_rt_xy(obj)
    if not AC8Runtime.isLiveObject(obj)then return nil,nil end
    local ok1, rt = pcall(function() return obj:get_property("RenderTransform") end)
    if not ok1 or rt == nil then return nil, nil end
    local ok2, tr = pcall(function() return rt.Translation end)
    if not ok2 or tr == nil then return nil, nil end
    return num_field(tr, { "X", "x" }), num_field(tr, { "Y", "y" })
end

local function get_rt_scale(obj)
    if not AC8Runtime.isLiveObject(obj)then return nil,nil end
    local ok1, rt = pcall(function() return obj:get_property("RenderTransform") end)
    if not ok1 or rt == nil then return nil, nil end
    local ok2, sc = pcall(function() return rt.Scale end)
    if not ok2 or sc == nil then return nil, nil end
    return num_field(sc, { "X", "x" }), num_field(sc, { "Y", "y" })
end

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
    
end

local function find_all_by_name(node_names)
    local out = {}
    local want = {}
    for _, n in ipairs(node_names) do want[n] = true end

    local seen = {}
    for _, cls in ipairs(SEARCH_CLASSES) do
        local ok, arr = pcall(function() return cls:get_objects_matching(false) end)
        if ok and type(arr) == "table" then
            for _, w in ipairs(arr) do
                local okn, nm = pcall(function() return w:get_full_name() end)
                if okn and type(nm) == "string"
                    and nm:find("/Engine/Transient", 1, true)
                    and nm:find(SCOPE, 1, true)      
                then
                    local l = nm:match("([^.]+)$") or ""

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

local function find_by_walk(from_patterns, node_names)
    if UW == nil then return nil, {} end
    local ok, arr = pcall(function() return UW:get_objects_matching(false) end)
    if not ok or type(arr) ~= "table" then return nil, {} end

    local want_node = {}
    for _, n in ipairs(node_names) do want_node[n] = true end

    for _, w in ipairs(arr) do
        local okn, nm = pcall(function() return w:get_full_name() end)
        if okn and type(nm) == "string" and nm:find("/Engine/Transient", 1, true) then
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

local function prepare_items(t)
    t.items = nil
    if t.objs == nil or #t.objs == 0 then return end
    local out = {}
    for i, o in ipairs(t.objs) do
        if AC8Runtime.isLiveObject(o) then
            local l = leaf(o)
            local base = l:gsub("_%d+$", "")
            local issub = false
            if t.subnames ~= nil then
                for _, nm in ipairs(t.subnames) do
                    if l == nm or base == nm then issub = true; break end
                end
            end
            out[#out + 1] = { o = o, k = path_of(o) or l, fn = full_name(o), sub = issub }
        end
    end
    if #out > 0 then
        t.items = out
    else
        t.items = nil
        t.objs = nil
    end

    t.opApplied, t.scApplied = nil, nil
end

local function find_node(from_patterns, node_names)
    local list = find_all_by_name(node_names)
    if #list == 0 then
        
        local w = find_by_walk(from_patterns, node_names)
        list = (w ~= nil) and { w } or {}
    end
    return prune_nested(list)
end

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

local function restore(e)
    if not AC8Runtime.isLiveObject(e.o)then return end
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

    local ok, cur = pcall(function() return o:GetRenderOpacity() end)
    if ok and type(cur) == "number" and math.abs(cur - 1.0) > 0.01 then
        pcall(function() o:SetRenderOpacity(1.0) end)
    end
end

local function apply_one(t)
    if not AC8Runtime.context.flight then return end

    -- 自己修復：もし未解決なら C.altimeter または resolve_all から即座に再取得
    if t.active and (t.items == nil or #t.items == 0) then
        if t.key == "ladder" and C and C.altimeter and AC8Runtime.isLiveObject(C.altimeter) then
            t.objs = { C.altimeter }
            prepare_items(t)
        else
            resolve_all(false)
        end
    end
    if t.items == nil or #t.items == 0 then return end

    if not t.active then
        if t.applied then
            for _, e in ipairs(t.items) do restore(e) end
            t.applied = false
        end
        t.opApplied, t.scApplied = nil, nil
        return
    end

    local op_dirty = (type(t.op) == "number" and t.op ~= t.opApplied)
    local sc_dirty = (type(t.sc) == "number" and t.sc ~= t.scApplied)

    for _, e in ipairs(t.items) do
        local o = e.o
        if not AC8Runtime.isLiveObject(o) then
            t.objs = nil
            t.items = nil
            t.applied = false
            return
        end
        remember(e)

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

        -- 可視性（Visibility）と透過度（RenderOpacity）の確実な復元（チュートリアル後などの非表示化対策）
        pcall(function()
            local curVis = o:GetVisibility()
            if curVis == 1 or curVis == 2 then
                o:SetVisibility(4)
            end
            local curOp = o:GetRenderOpacity()
            local targetOp = (type(t.op) == "number") and t.op or 1.0
            if type(curOp) == "number" and curOp < 0.1 then
                o:SetRenderOpacity(targetOp)
            end
        end)

        if op_dirty then
            pcall(function() o:SetRenderOpacity(t.op) end)
        end
        if sc_dirty then
            pcall(function() o:SetRenderScale({ X = t.sc, Y = t.sc }) end)
        end
    end

    if op_dirty then t.opApplied = t.op end
    if sc_dirty then t.scApplied = t.sc end
    t.applied = true
end

local workshop_after, workshop_poll
local workshop_active=false
local function apply()
    -- Handled exclusively by AC8_VR-HUDLayout.lua to eliminate frame fight and allow integrated positioning
    -- for _, t in ipairs(TARGETS) do
    --     local ok, err = pcall(apply_one, t)
    --     if not ok then end
    -- end
    if workshop_after then pcall(workshop_after) end
end



local function cfg_by_key(k)
    for _, t in ipairs(TARGETS) do
        if t.key == k then return t end
    end
    return nil
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
    tg.opApplied, tg.scApplied = nil, nil
    return true
end

local function read_cfg()
    if not HAS_JSON then return nil end
    local ok, t = pcall(function() return json.load_file(CFG_FILE) end)
    if not ok or type(t) ~= "table" then return nil end
    return t
end

-- Preserve existing player instrument overrides. This reader remains even
-- though the old developer tuning panel and its save button were removed.
local function load_cfg()
    local t = read_cfg()
    if t == nil then return false end
    local n = 0
    for k, v in pairs(t) do
        local tg = cfg_by_key(k)
        if tg ~= nil and apply_cfg_entry(tg, v) then n = n + 1 end
    end
    return n > 0
end

local function load_cfg_one(tg)
    local all = read_cfg()
    if all == nil then return false end
    local v = all[tg.key]
    if v == nil then return false end
    return apply_cfg_entry(tg, v)
end

local function resolve_all(verbose)
    for _, t in ipairs(TARGETS) do
        if t.objs == nil or #t.objs == 0 or verbose then
            if t.key == "ladder" and C and C.altimeter and AC8Runtime.isLiveObject(C.altimeter) then
                t.objs = { C.altimeter }
            else
                local found = find_node(t.from, t.nodes)
                t.objs = (found and #found > 0) and found or nil
            end
            prepare_items(t)
            if verbose then
                if t.objs and #t.objs > 0 then
                    for i, o in ipairs(t.objs) do
                        
                    end
                else
                    local _, chain = find_by_walk(t.from, t.nodes)
                    
                end
            end
        end
    end
end

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
        
    end
end

local rescan_idx = 1


load_cfg()

resolve_all(true)

local layout_scope_sync
local function lt14_apply()apply()end
pcall(function()uevr.sdk.callbacks.on_pre_viewport_client_draw(function()
 if rawget(_G, 'AC8Runtime') and AC8Runtime.profileCount then AC8Runtime.profileCount('ladderDraw') end
 if not layout_scope_sync or not layout_scope_sync()then return end
 -- Handled exclusively by AC8_VR-HUDLayout.lua to eliminate frame fight and allow full pitch ladder positioning
 -- for _,t in ipairs(TARGETS)do if t.key=='ladder'then pcall(apply_one,t)end end
end)end)

-- widget reflection/writes run on the game thread. The old pre-Slate
-- callback could retain dead flight widgets and block the shared Lua lock.

local WS = {revision="none", groups={}, components={}, catalog={}, entries={}, originals={},
    groupbase={}, states={}, elapsed=0, scan_elapsed=15, rescan=-1, restore=false}
local WS_GROUPS = {ladder=true, radar=true, info=true}
for _, t in ipairs(TARGETS) do
    if WS_GROUPS[t.key] then
        WS.groupbase[t.key] = {active=t.active,x=t.x,y=t.y,sc=t.sc,op=t.op,
            sdx=t.sdx,sdy=t.sdy}
    end
end
local function ws_params(p)
    return type(p)=="table" and type(p.enabled)=="boolean"
        and type(p.x)=="number" and p.x>=-4000 and p.x<=4000
        and type(p.y)=="number" and p.y>=-4000 and p.y<=4000
        and type(p.scale)=="number" and p.scale>=0.1 and p.scale<=3
end


local function ws_identify()
    local selected_root = nil
    WS.canvasRoot=nil
    if UW then
        local ok, arr = pcall(function() return UW:get_objects_matching(false) end)
        if ok and type(arr)=="table" then
            for _, w in ipairs(arr) do
                local nm=full_name(w)
                if type(nm)=="string" and nm:find("/Engine/Transient",1,true)
                    and nm:find(SCOPE,1,true) and not nm:find(".WidgetTree",1,true)
                    and call(w,"IsInViewport")==true then
                    selected_root=nm:match("%s(.+)$");WS.canvasRoot=w; break
                end
            end
        end
    end
    local entries, catalog, seen = {}, {}, {}
    if not selected_root then WS.entries={};WS.catalog={};return end
    
    local excluded = {}
    for _, t in ipairs(TARGETS) do
        if WS_GROUPS[t.key] and t.items then
            for _, e in ipairs(t.items) do
                excluded[full_name(e.o)]=true
            end
        end
    end
    local skip={BaseCanvas=true,MainCanvas=true,DynamicDrawCanvas=true,WorldToScreenDrawCanvas=true,
        LowestPriorityCanvasWorldToScreenDraw=true,LowestPriorityDynamicDrawCanvas=true,TopPriorityCanvas=true}
    for _, cls in ipairs(SEARCH_CLASSES) do
        local ok, arr=pcall(function() return cls:get_objects_matching(false) end)
        if ok and type(arr)=="table" then
            for _, o in ipairs(arr) do
                local nm=full_name(o)
                local path=type(nm)=="string" and nm:match("%s(.+)$") or nil
                if path and path:sub(1,#selected_root+1)==selected_root.."." and not excluded[nm] then
                    local name=leaf(o)
                    local id=path:sub(#selected_root+2):gsub("WidgetTree_%d+","WidgetTree"):gsub("_C_%d+","_C")
                    local targetComponent=name=="WBP_LocatorWidget" or name=="WBP_TargetSelectionDraw"
                    if not skip[name] and not seen[id] and (targetComponent or (not name:find("Target") and not name:find("Locator") and not name:find("Seeker") and not name:find("Reticle"))) then
                        seen[id]=true
                        local category="Other flight HUD"
                        if path:find("ChroniclePersistent",1,true) then category="Central instruments"
                        elseif path:find("HUDMessageWidget",1,true) then category="Comms and messages"
                        elseif path:find("MiniMap",1,true) then category="Radar"
                        elseif path:find("PlayerState",1,true) then category="Aircraft and weapons" end
                        local vis=call(o,"GetVisibility")
                        local sx,sy=get_rt_scale(o);local x,y=get_rt_xy(o)
                        if targetComponent then category="Target components" end
                        entries[id]={o=o,k=nm,fn=nm,scaleOnly=targetComponent}
                        catalog[#catalog+1]={id=id,name=name,category=category,path=id,
                            visibility=vis or -1,x=x or 0,y=y or 0,scaleX=sx or 1,scaleY=sy or 1,scaleOnly=targetComponent,}
                    end
                end
            end
        end
    end

    local scoreClass=api:find_uobject("Class /Script/UMG.Widget")
    if scoreClass then
        local ok,arr=pcall(function() return scoreClass:get_objects_matching(false) end)
        if ok and type(arr)=="table" then
            for _,o in ipairs(arr) do
                local nm=full_name(o)
                local path=type(nm)=="string" and nm:match("%s(.+)$") or nil
                local name=leaf(o)
                local radioLabel=path and path:find('WBP_HUD_SubWidgets_Parts_RadioText_000',1,true)
                    and (name=='SpeakerNameText' or name=='SubTitleMessageText')
                if path and type(name)=="string" and (name:lower():find("score",1,true) or radioLabel)
                    and path:sub(1,#selected_root+1)==selected_root.."." and not excluded[nm] then
                    local id=path:sub(#selected_root+2):gsub("WidgetTree_%d+","WidgetTree"):gsub("_C_%d+","_C")
                    if not seen[id] then
                        seen[id]=true
                        local sx,sy=get_rt_scale(o);local x,y=get_rt_xy(o)
                        entries[id]={o=o,k=nm,fn=nm}
                        catalog[#catalog+1]={id=id,name=name,category=radioLabel and "Radio text labels" or "Score readouts",path=id,
                            visibility=call(o,"GetVisibility") or -1,x=x or 0,y=y or 0,
                            scaleX=sx or 1,scaleY=sy or 1,}
                    end
                end
            end
        end
    end
    table.sort(catalog,function(a,b) return a.category..a.name < b.category..b.name end)
    WS.entries,WS.catalog=entries,catalog
end
local function ws_transform(entry,p,tag)
    local o,k=entry.o,entry.k
    local base=WS.originals[k]
    if not p.enabled and not base then WS.states[tag]="Unchanged";return end
    local ok,err=pcall(function()
        if not base then
            local x,y=get_rt_xy(o);local sx,sy=get_rt_scale(o)
            assert(x and y and sx and sy,"Original transform unavailable")
            base={x=x,y=y,sx=sx,sy=sy};WS.originals[k]=base
        end
        local x=base.x+(p.enabled and p.x or 0)
        local y=base.y+(p.enabled and p.y or 0)
        local scale=p.enabled and p.scale or 1
        local cx,cy=get_rt_xy(o);local sx,sy=get_rt_scale(o)
        if not entry.scaleOnly and (not cx or math.abs(cx-x)>0.01 or not cy or math.abs(cy-y)>0.01) then
            o:SetRenderTranslation({X=x,Y=y})
        end
        if not sx or math.abs(sx-base.sx*scale)>0.001 or not sy or math.abs(sy-base.sy*scale)>0.001 then
            o:SetRenderScale({X=base.sx*scale,Y=base.sy*scale})
        end
        cx,cy=get_rt_xy(o);sx,sy=get_rt_scale(o)
        assert(cx and cy and sx and sy and (entry.scaleOnly or (math.abs(cx-x)<1 and math.abs(cy-y)<1))
            and math.abs(sx-base.sx*scale)<0.01 and math.abs(sy-base.sy*scale)<0.01,"Transform read-back differs")
        if not p.enabled then WS.originals[k]=nil end
    end)
    WS.states[tag]=ok and (p.enabled and "Write verified; check headset" or "Restored") or ("Error: "..tostring(err))
end

local function ws_field(o,k)
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
end
local function ws_slot_copy(slot)
    local offsets=ws_field(slot,"Offsets");local anchors=ws_field(slot,"Anchors")
    local alignment=ws_field(slot,"Alignment")
    if not offsets or not anchors or not alignment then return nil end
    local min=ws_field(anchors,"Minimum");local max=ws_field(anchors,"Maximum")
    if not min or not max then return nil end
    local out={Offsets={},Anchors={Minimum={},Maximum={}},Alignment={}}
    for _,k in ipairs({"Left","Top","Right","Bottom"}) do
        local v=tonumber(ws_field(offsets,k));if not v then return nil end;out.Offsets[k]=v
    end
    for _,k in ipairs({"X","Y"}) do
        local a=tonumber(ws_field(min,k));local b=tonumber(ws_field(max,k));local c=tonumber(ws_field(alignment,k))
        if not a or not b or not c then return nil end
        out.Anchors.Minimum[k]=a;out.Anchors.Maximum[k]=b;out.Alignment[k]=c
    end
    out.ZOrder=tonumber(ws_field(slot,"ZOrder")) or 0
    local auto=ws_field(slot,"bAutoRemoveOnWorldRemoved")
    if type(auto)~="boolean" then return nil end
    out.bAutoRemoveOnWorldRemoved=auto
    return out
end
local function ws_canvas_capture(root)
    local key=full_name(root)
    if WS.canvasBase and WS.canvasBase.key==key then return WS.canvasBase end
    local b={key=key,clipping=call(root,"GetClipping")}
    local cls=api:find_uobject("Class /Script/UMG.GameViewportSubsystem")
    if cls then
        local ok,arr=pcall(function() return cls:get_objects_matching(false) end)
        if ok and type(arr)=="table" then
            for _,sub in ipairs(arr) do
                if call(sub,"IsWidgetAdded",root)==true then
                    local slot=call(sub,"GetWidgetSlot",root)
                    local copy=slot and ws_slot_copy(slot)
                    if copy then b.slot=copy;b.subsystem=sub;break end
                end
            end
        end
    end
    WS.canvasBase=b;return b
end
local function ws_canvas_apply()
    local p=WS.canvas;local root=WS.canvasRoot
    if not p then return end
    if not root then WS.states.canvas="MainFlight canvas not found";return end
    if not p.enabled and not WS.canvasBase then WS.states.canvas="Canvas unchanged";return end
    local ok,err=pcall(function()
        local b=ws_canvas_capture(root)
        ws_transform({o=root,k=b.key},p,"canvas")
        assert(not WS.states.canvas or WS.states.canvas:sub(1,6)~="Error:",WS.states.canvas)
        local extraW=p.enabled and p.extraWidth or 0
        local extraH=p.enabled and p.extraHeight or 0
        if b.slot then
            local target=ws_slot_copy(b.slot)
            local a=target.Anchors
            target.Offsets.Right=target.Offsets.Right+extraW*(a.Maximum.X~=a.Minimum.X and -1 or 1)
            target.Offsets.Bottom=target.Offsets.Bottom+extraH*(a.Maximum.Y~=a.Minimum.Y and -1 or 1)
            local current=call(b.subsystem,"GetWidgetSlot",root)
            local c=current and ws_slot_copy(current)
            assert(c,"Viewport slot read-back unavailable")
            if math.abs(c.Offsets.Right-target.Offsets.Right)>.01 or math.abs(c.Offsets.Bottom-target.Offsets.Bottom)>.01 then
                b.subsystem:SetWidgetSlot(root,target)
                b.resized=true
            end
            c=ws_slot_copy(call(b.subsystem,"GetWidgetSlot",root))
            assert(c and math.abs(c.Offsets.Right-target.Offsets.Right)<1 and math.abs(c.Offsets.Bottom-target.Offsets.Bottom)<1,"Viewport size read-back differs")
        elseif extraW~=0 or extraH~=0 then
            WS.states.canvas="Transform applied; layout expansion unavailable: viewport slot could not be captured"
        end
        if p.enabled and p.inheritClip then
            assert(type(b.clipping)=="number","Original root clipping unavailable")
            root:SetClipping(0);b.clipChanged=true
            assert(call(root,"GetClipping")==0,"Root clipping read-back differs")
        elseif b.clipChanged then root:SetClipping(b.clipping);b.clipChanged=false end
        if not p.enabled then WS.states.canvas="Canvas baseline restored" end
    end)
    if not ok then WS.states.canvas="Canvas error: "..tostring(err) end
end

local function ws_ancestor_conflict(id)

    for other,p in pairs(WS.components) do
        if other~=id and p.enabled and id:sub(1,#other+1)==other.."." then return true end
    end
    return false
end
workshop_after=function()
    if WS.elapsed%20==0 then pcall(ws_canvas_apply) end
    for _, t in ipairs(TARGETS) do
        local p=WS.groups[t.key]
        if p and WS_GROUPS[t.key] then
            local tag="group:"..t.key
            if not t.items or #t.items==0 then WS.states[tag]="Not found in this mission"
            elseif WS.groupbase[t.key].active then
                
                local b=WS.groupbase[t.key]
                local verified=true
                for _,e in ipairs(t.items) do
                    local x,y=get_rt_xy(e.o);local sx,sy=get_rt_scale(e.o)
                    local tx=t.x+(e.sub and (t.sdx or 0) or 0)
                    local ty=t.y+(e.sub and (t.sdy or 0) or 0)
                    verified=verified and x~=nil and y~=nil and sx~=nil and sy~=nil
                        and math.abs(x-tx)<1 and math.abs(y-ty)<1 and math.abs(sx-t.sc)<0.01 and math.abs(sy-t.sc)<0.01
                end
                WS.states[tag]=verified and (p.enabled and "Write verified; check headset" or "Herbert baseline") or "Waiting for transform read-back"
            else
                local results={}
                for _,e in ipairs(t.items) do
                    ws_transform({o=e.o,k=full_name(e.o)},p,tag)
                    results[#results+1]=WS.states[tag]
                end
                for _,s in ipairs(results) do if s:sub(1,6)=="Error:" then WS.states[tag]=s;break end end
            end
        end
    end
    for id,p in pairs(WS.components) do
        local tag="component:"..id
        local entry=WS.entries[id]
        if not entry then WS.states[tag]="Not found in this mission"
        elseif p.enabled and ws_ancestor_conflict(id) then
            ws_transform(entry,{enabled=false,x=0,y=0,scale=1},tag)
            WS.states[tag]="Disable the parent component first"
        else ws_transform(entry,p,tag) end
    end
end
workshop_poll=function()
    if WS.hudEpoch~=AC8Runtime.context.epoch then
        WS.hudEpoch=AC8Runtime.context.epoch;WS.elapsed=19;WS.needScan=true;WS.acquireUntil=AC8Runtime.tick+120
    end
    if not AC8Runtime.context.flight then return end
    WS.elapsed=WS.elapsed+1;WS.scan_elapsed=WS.scan_elapsed+1
    if WS.elapsed%20~=0 then return end
    local ok,cmd=pcall(function() return json.load_file("ac8_workshop_v2_controls.json") end)
    if ok and type(cmd)=="table" and type(cmd.revision)=="string" and cmd.revision~=WS.revision
        and type(cmd.groups)=="table" and type(cmd.components)=="table" then
        local valid=true;local n=0
        for k in pairs(WS_GROUPS) do if not ws_params(cmd.groups[k]) then valid=false end end
        for id,p in pairs(cmd.components) do
            n=n+1;if type(id)~="string" or not ws_params(p) or n>24 then valid=false end
        end
        if cmd.canvas then
            local c=cmd.canvas
            valid=valid and ws_params(c) and type(c.extraWidth)=="number" and c.extraWidth>=0 and c.extraWidth<=4000
                and type(c.extraHeight)=="number" and c.extraHeight>=0 and c.extraHeight<=4000 and type(c.inheritClip)=="boolean"
        end
        if valid then
            WS.canvas=cmd.canvas or {enabled=false,x=0,y=0,scale=1,extraWidth=0,extraHeight=0,inheritClip=false}
            
            for id in pairs(WS.components) do
                if not cmd.components[id] then cmd.components[id]={enabled=false,x=0,y=0,scale=1} end
            end
            workshop_active=true
            WS.groups,WS.components=cmd.groups,cmd.components
            for _,t in ipairs(TARGETS) do
                local p=WS.groups[t.key];local b=WS.groupbase[t.key]
                if p and b and b.active then
                    t.x=b.x+(p.enabled and p.x or 0);t.y=b.y+(p.enabled and p.y or 0)
                    t.sc=b.sc*(p.enabled and p.scale or 1);t.active=b.active
                    t.scApplied=nil
                end
            end
            WS.revision=cmd.revision
            if cmd.rescan~=WS.rescan then WS.rescan=cmd.rescan;WS.needScan=true end
        end
    end
    local missing=#WS.catalog==0
    for id,p in pairs(WS.components)do if p.enabled and not WS.entries[id]then missing=true;break end end
    if WS.needScan or (missing and AC8Runtime.tick<(WS.acquireUntil or 0) and WS.scan_elapsed>=60) then
        WS.needScan=false
        WS.scan_elapsed=0
        pcall(rescan_all)
        pcall(ws_identify)
    end
    
    pcall(apply)
    if WS.elapsed%60==0 then
        
    end
end
pcall(ws_identify)

local layoutEpoch=-1
layout_scope_sync=function()
 local context=AC8Runtime.context
 if layoutEpoch~=context.epoch then
  layoutEpoch=context.epoch
  -- Forget old-world pointers without trying to restore destroyed widgets.
  for _,t in ipairs(TARGETS)do t.objs=nil;t.items=nil;t.applied=false;t.opApplied=nil;t.scApplied=nil end
  WS.entries={};WS.originals={};WS.catalog={};WS.canvasRoot=nil;WS.canvasBase=nil
  WS.needScan=true;WS.elapsed=19;WS.scan_elapsed=20;WS.acquireUntil=AC8Runtime.tick+120
  if context.flight then pcall(resolve_all,false)end
 end
 -- 飛行中にラダーが未解決の場合は即座に再取得（チュートリアル復帰直後の遅延生成対策）
 if context.flight and TARGETS[1] and (TARGETS[1].items == nil or #TARGETS[1].items == 0) then
  pcall(resolve_all, false)
 end
 return context.flight==true
end
local ticks = 0
pcall(function()
    uevr.sdk.callbacks.on_post_engine_tick(function()
        if not layout_scope_sync()then return end
        if workshop_poll then pcall(workshop_poll) end
        lt14_apply("post_engine_tick")
        ticks = ticks + 1

    end)
end)

end)(AC8Runtime.host('layout','inherited instrument controls'),AC8Runtime.json,AC8Runtime.log)
end
end


end

if registry.start then registry.start() end
