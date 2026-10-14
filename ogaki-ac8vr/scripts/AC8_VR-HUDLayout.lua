-- Final HUD placements: campaign rows, velocity/forward locators, wingman/radar,
-- loading indicator and bomb attachments. Presentation defaults below run once
-- per Lua session; recurring placement services have their own bounded cadence.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.

-- EDITABLE HUD PRESENTATION DEFAULTS (UEVR UI settings, not world/camera scale).
-- Applied once per Lua session. Later UEVR menu edits are left alone, including
-- across missions and radar modes. Edit here for the next launch/script reload.
-- Set enabled=false to use your own saved UEVR settings instead.
-- depth = UI distance in metres; scale = UI size multiplier;
-- curvature = cylinder angle in degrees. Applying this also selects curved UI.
-- Validation bounds: depth/scale 0.01..100, curvature 1..359. No save_config call.
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
assert(not registry.sections['hud_layout'], 'Duplicate AC8 VR section: hud_layout')
registry.sections['hud_layout'] = function(R)
-- Own final VR HUD positioning and ordered inherited layout services.
-- A single startup transaction; never enforce these settings every frame.
-- Defer while cinematic restoration owns the UI, so it cannot undo the preset.
local presentation={done=false,status='waiting'}
R.hudPresentationDefaults=presentation
local function applyPresentationDefaults()
 if presentation.done then return end
 if HUD_PRESENTATION.enabled==false then presentation.done=true;presentation.status='disabled';return end
 local settings={
  {key='UI_Distance',value=HUD_PRESENTATION.depth,min=.01,max=100},
  {key='UI_Size',value=HUD_PRESENTATION.scale,min=.01,max=100},
  {key='UI_Cylinder_Angle',value=HUD_PRESENTATION.curvature,min=1,max=359},
  {key='UI_OverlayType',value=1,min=1,max=1},
 }
 for _,setting in ipairs(settings)do
  local v=setting.value
  if type(v)~='number'or v~=v or v<setting.min or v>setting.max then
   presentation.done=true;presentation.status='invalid '..setting.key
   R.errors.hudPresentationDefaults=presentation.status;return
  end
 end
 local ci=rawget(_G,'AC8_CinematicIntent')
 if ci and(ci.maskActive or ci.hangarActive or ci.recoveringUI or ci.guardForced or
    (ci.saved and next(ci.saved)~=nil)or(ci.hangarSaved and next(ci.hangarSaved)~=nil))then return end
 local function read(key)
  local ok,v=pcall(function()return uevr.params.vr:get_mod_value(key)end)
  local n=ok and tonumber(v)
  if n and n==n and math.abs(n)<1e9 then return n end
 end
 local before={}
 for _,setting in ipairs(settings)do
  local value=read(setting.key)
  if value==nil then presentation.status='waiting for UEVR UI settings';return end
  before[setting.key]=value
 end
 -- Once a write is attempted, never retry later over a user's menu adjustment.
 presentation.done=true
 local changed={}
 for _,setting in ipairs(settings)do
  if math.abs(before[setting.key]-setting.value)>.0001 then
   changed[#changed+1]=setting.key
   local ok=pcall(function()uevr.params.vr.set_mod_value(setting.key,tostring(setting.value))end)
   local actual=read(setting.key)
   if not ok or not actual or math.abs(actual-setting.value)>.0001 then
    for i=#changed,1,-1 do
     local key=changed[i];pcall(function()uevr.params.vr.set_mod_value(key,tostring(before[key]))end)
    end
    presentation.status='UEVR write failed; previous values restored where possible'
    R.errors.hudPresentationDefaults=presentation.status;return
   end
  end
 end
 presentation.status='applied once; UEVR menu changes now take priority'
end
applyPresentationDefaults()
R.host('layout','HUD presentation defaults').sdk.callbacks.on_post_engine_tick(applyPresentationDefaults)

AC8Runtime.layoutEnabled=true
for i,setup in ipairs(AC8Runtime.inheritedSetup)do local ok,err=pcall(setup);if not ok then AC8Runtime.errors['inherited layout '..i]=tostring(err)end end
AC8Runtime.inheritedSetup={}

do
-- ac8 campaign target row
(function(uevr,json,print)


local api=uevr.api
local old=rawget(_G,'AC8_CampaignTargetRow')
if old then old.stopped=true;if old.restore then old.restore() end end
local S={version=2,ticks=0,enabled=true,stopped=false,status='waiting for flight HUD'}
rawset(_G,'AC8_CampaignTargetRow',S)
local function call(o,k,...)
    if o~=uevr.api and not AC8Runtime.isLiveObject(o)then return nil end
    if not o then return nil end
    local ok,v=pcall(function(...) return o[k](o,...) end,...);if ok then return v end
end
local function field(o,k) local ok,v=pcall(function() return o[k] end);if ok then return v end end
local function full(o) return call(o,'get_full_name') end
local function xy(v)
    local x=field(v,'X') or field(v,'x');local y=field(v,'Y') or field(v,'y')
    if type(x)=='number' and type(y)=='number' and x==x and y==y then return {X=x,Y=y} end
end
local function transform(o)
    if not AC8Runtime.isLiveObject(o)then return nil,nil end
    local r=call(o,'get_property','RenderTransform')
    return xy(field(r,'Translation')),xy(field(r,'Scale'))
end
local slate=call(call(api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary'),'get_class_default_object')
local function paintedGeometry(o)
    return call(o,'GetPaintSpaceGeometry') or call(o,'GetCachedGeometry')
end
local function geometry(o)
    local g=paintedGeometry(o);local size=xy(call(slate,'GetLocalSize',g))
    if not size or size.X<=0 or size.Y<=0 then return nil end
    local left=xy(call(slate,'LocalToAbsolute',g,{X=0,Y=size.Y/2}))
    return left,g
end
function S.restore()
    if S.base and S.row and full(S.row)==S.base.name then
        pcall(function() S.row:SetRenderTranslation(S.base.translation);S.row:SetRenderScale(S.base.scale) end)
    end
    S.base=nil;S.row=nil;S.widgets=nil
end
local function discard()S.base=nil;S.row=nil;S.widgets=nil end
local function discover()
    -- Fast path: use shared HUD refs from InheritedHUD
    local refs = AC8Runtime and AC8Runtime.hudLayoutRefs
    local camp = refs and refs.campaign
    if camp and AC8Runtime.isLiveObject(camp) then
        local targetText = call(camp, 'get_property', 'TargetText')
        local targetInfo = call(camp, 'get_property', 'TargetInfoText')
        local privateScore = call(camp, 'get_property', 'PrivateScore')
        local timeText = call(camp, 'get_property', 'TimeText')
        if targetText and targetInfo and privateScore and timeText then
            local row = call(targetText, 'GetParent')
            if row and full(row) == full(call(targetInfo, 'GetParent')) then
                local t, sc = transform(row)
                if t and sc then
                    S.widgets = { TargetText = targetText, TargetInfoText = targetInfo, PrivateScore = privateScore, TimeText = timeText }
                    S.row = row
                    S.base = { name = full(row), translation = t, scale = sc }
                    return
                end
            end
        end
    end
    S.status = 'waiting for shared campaign info ref'
end
local function apply()
    if S.stopped then return end
    S.ticks=S.ticks+1
    
    local hud=full(call(call(api,'get_player_controller',0),'GetHUD')) or ''
    if not hud:match('^LiveMainHUDParent4K_C ')then discard();return end
    if not S.enabled then S.restore();return end
    if S.hud~=hud then discard();S.hud=hud end
    if S.row and full(S.row)~=S.base.name then S.restore() end
    if not S.row then
        if S.ticks < (S.nextDiscover or 0) then return end
        S.nextDiscover = S.ticks + 60
        discover()
        if not S.row then
            S.nextDiscover = S.ticks + 90
            return
        end
    end
    local w=S.widgets
    local cfgOK,cfg=pcall(function()return json.load_file('ac8_workshop_v2_controls.json')end)
    local revision=cfgOK and type(cfg)=='table'and cfg.revision or nil
    local rowName=full(S.row)or '';local scope=(rowName:match('^(%S+)')or '')..':'..(rowName:match('%.([^%.]+)$')or rowName:match('%s(.+)$')or '')
    if S.cacheRow~=rowName then
        S.cacheRow=rowName
        local ok,cached=pcall(function()return json.load_file('ac8_hud_layout_cache.json')end)
        local _,scoreScale=transform(w.PrivateScore)
        if ok and type(cached)=='table'and cached.version==1 and revision and cached.revision==revision and cached.scope==scope
            and type(cached.x)=='number'and type(cached.y)=='number'and math.abs(cached.x)<4000 and math.abs(cached.y)<4000
            and scoreScale and type(cached.scale)=='table'and type(cached.scale.X)=='number'and type(cached.scale.Y)=='number'
            and math.abs(cached.scale.X-scoreScale.X)<.001 and math.abs(cached.scale.Y-scoreScale.Y)<.001 then
            S.row:SetRenderScale(scoreScale);S.row:SetRenderTranslation({X=cached.x,Y=cached.y});S.status='saved coherent row applied';return
        end
    end
    local score=geometry(w.PrivateScore);local time=geometry(w.TimeText)
    local target=geometry(w.TargetText);local _,scoreScale=transform(w.PrivateScore)
    if not score or not time or not target or not scoreScale then S.status='waiting for painted geometry';return end
    
    local current,sc=transform(S.row)
    local parent=call(S.row,'GetParent');local g=paintedGeometry(parent)
    local p=xy(call(slate,'LocalToAbsolute',g,{X=0,Y=0}))
    local px=xy(call(slate,'LocalToAbsolute',g,{X=1,Y=0}))
    local py=xy(call(slate,'LocalToAbsolute',g,{X=0,Y=1}))
    if not p or not px or not py then S.status='parent geometry unavailable';return end
    local ax,ay,bx,by=px.X-p.X,px.Y-p.Y,py.X-p.X,py.Y-p.Y
    local det=ax*by-ay*bx
    local gap=math.abs(score.Y-time.Y)
    if math.abs(det)<.000001 or gap<1 or gap>500 then S.status='invalid geometry or spacing; unchanged';return end
    local goal=math.max(score.Y,time.Y)+gap
    local predicted={X=target.X,Y=target.Y}
    if math.abs(sc.X-scoreScale.X)>.001 or math.abs(sc.Y-scoreScale.Y)>.001 then
        local rg=paintedGeometry(S.row);local localPoint=xy(call(slate,'AbsoluteToLocal',rg,target));local size=xy(call(slate,'GetLocalSize',rg))
        local origin=xy(call(slate,'LocalToAbsolute',rg,{X=0,Y=0}));local ex=xy(call(slate,'LocalToAbsolute',rg,{X=1,Y=0}));local ey=xy(call(slate,'LocalToAbsolute',rg,{X=0,Y=1}))
        local pivot=xy(call(S.row,'GetRenderTransformPivot')or call(S.row,'get_property','RenderTransformPivot'))
        if not localPoint or not size or not origin or not ex or not ey or not pivot or math.abs(sc.X)<.00001 or math.abs(sc.Y)<.00001 then S.status='waiting for valid row geometry';return end
        local x=(localPoint.X-pivot.X*size.X)*(scoreScale.X/sc.X-1)
        local y=(localPoint.Y-pivot.Y*size.Y)*(scoreScale.Y/sc.Y-1)
        predicted.X=target.X+(ex.X-origin.X)*x+(ey.X-origin.X)*y
        predicted.Y=target.Y+(ex.Y-origin.Y)*x+(ey.Y-origin.Y)*y
    end
    local dx=score.X-predicted.X;local dy=goal-predicted.Y
    local x=current.X+(dx*by-dy*bx)/det;local y=current.Y+(dy*ax-dx*ay)/det
    if math.abs(x)>4000 or math.abs(y)>4000 then S.status='computed translation out of range';return end
    if math.abs(sc.X-scoreScale.X)>.001 or math.abs(sc.Y-scoreScale.Y)>.001 then S.row:SetRenderScale(scoreScale)end
    if math.abs(dx)>.5 or math.abs(dy)>.5 then S.row:SetRenderTranslation({X=x,Y=y})end
    local checked=transform(S.row)
    S.status=checked and math.abs(checked.X-x)<1 and math.abs(checked.Y-y)<1
        and 'transform verified; visual placement pending' or 'transform readback failed'
    if revision and S.measured and math.abs(S.measured.x-x)<.1 and math.abs(S.measured.y-y)<.1 then
        local last=S.savedCache
        if not last or last.revision~=revision or last.scope~=scope or math.abs(last.x-x)>.5 or math.abs(last.y-y)>.5 then
            local cached={version=1,revision=revision,scope=scope,x=x,y=y,scale=scoreScale}
            pcall(function()json.dump_file('ac8_hud_layout_cache.json',cached,2)end);S.savedCache=cached
        end
    end
    S.measured={scoreY=score.Y,timeY=time.Y,gap=gap,targetRequestedY=goal,x=x,y=y}
end
uevr.sdk.callbacks.on_post_engine_tick(function()
    local ok,err=pcall(apply);if not ok then S.status=tostring(err) end
    if not S.stopped and S.ticks%120==0 then
        
    end
end)
pcall(function() uevr.sdk.callbacks.on_script_reset(S.restore) end)

end)(AC8Runtime.host('layout','ac8_campaign_target_row.lua'),AC8Runtime.json,AC8Runtime.log)
end

do
-- ac8 velocity alignment
(function(uevr,json,print)


local api=uevr.api
local old=rawget(_G,'AC8_VelocityAlignment')
if old then old.stopped=true;if old.restore then old.restore() end end
local S={version=6,enabled=true,ticks=0,stopped=false,status='waiting for flight HUD',
    offsetX=-2058,offsetY=-1080,iconX=1920,iconY=1087,slowInterval=600}
rawset(_G,'AC8_VelocityAlignment',S)
local function call(o,k,...)
    if o~=uevr.api and not AC8Runtime.isLiveObject(o)then return nil end
    if not o then return nil end
    local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function full(o)return call(o,'get_full_name')end
local function xy(v)
    local x,y=field(v,'X'),field(v,'Y')
    if type(x)=='number' and type(y)=='number' and x==x and y==y then return {X=x,Y=y} end
end
local function transform(o)
    if not AC8Runtime.isLiveObject(o)then return nil,nil end
    local r=call(o,'get_property','RenderTransform')
    return xy(field(r,'Translation')),xy(field(r,'Scale'))
end
local function matches(a,b,tolerance)
    return a and b and math.abs(a.X-b.X)<tolerance and math.abs(a.Y-b.Y)<tolerance
end
local function redraw()
    call(S.velocity,'InvalidateLayoutAndVolatility')
    local parent=call(S.velocity,'GetParent')
    for _=1,8 do
        if not parent then break end
        if (full(parent) or ''):match('^RetainerBox ') then call(parent,'RequestRender') end
        parent=call(parent,'GetParent')
    end
end
function S.restore()
    for _,r in ipairs(S.originals or {})do
        if full(r.object)==r.name then
            call(r.object,'SetRenderTranslation',r.translation);call(r.object,'SetRenderScale',r.scale)
        end
    end
    S.velocity=nil;S.icon=nil;S.altimeter=nil;S.root=nil;S.originals=nil;S.lastIconPin=nil
end
local function discard()S.velocity=nil;S.icon=nil;S.altimeter=nil;S.root=nil;S.originals=nil;S.lastIconPin=nil end
local function discover()
    -- Fast path: use shared HUD refs from InheritedHUD
    local refs = AC8Runtime and AC8Runtime.hudLayoutRefs
    if refs and refs.vel and refs.vicon and refs.altimeter and refs.root then
        local originals = {}
        for _, o in ipairs({ refs.vel, refs.vicon }) do
            local t, sc = transform(o)
            if not t or not sc then return end
            originals[#originals + 1] = { object = o, name = full(o), translation = t, scale = sc }
        end
        S.velocity = refs.vel; S.icon = refs.vicon; S.altimeter = refs.altimeter; S.root = refs.root; S.originals = originals
        return
    end
end
local function apply()
    if S.stopped then return end
    S.ticks=S.ticks+1;if S.ticks%4~=0 then return end
    local hud=full(call(call(api,'get_player_controller',0),'GetHUD')) or ''
    if not hud:match('^LiveMainHUDParent4K_C ')then discard();return end
    if not S.enabled then S.restore();return end
    if S.hud~=hud then discard();S.hud=hud end
    if S.root and call(S.root,'IsInViewport')~=true then S.restore() end
    if not S.velocity then
        if S.ticks < (S.nextDiscover or 0) then return end
        S.nextDiscover = S.ticks + 60
        discover()
        if not S.velocity then
            S.nextDiscover = S.ticks + 90
            return
        end
    end
    local ladder,scale=transform(S.altimeter);if not ladder or not scale then return end
    local wanted={X=ladder.X+S.offsetX,Y=ladder.Y+S.offsetY}
    local translation,currentScale=transform(S.velocity);local changed=false
    if not matches(translation,wanted,.01) then call(S.velocity,'SetRenderTranslation',wanted);changed=true end
    if not matches(currentScale,scale,.001) then call(S.velocity,'SetRenderScale',scale);changed=true end

    if not S.lastIconPin or S.ticks-S.lastIconPin>=S.slowInterval then
        local iconTranslation,iconScale=transform(S.icon)
        local iconWanted={X=S.iconX,Y=S.iconY};local unit={X=1,Y=1}
        if not matches(iconTranslation,iconWanted,.01) then call(S.icon,'SetRenderTranslation',iconWanted);changed=true end
        if not matches(iconScale,unit,.001) then call(S.icon,'SetRenderScale',unit);changed=true end
        S.lastIconPin=S.ticks
    end
    if changed then redraw() end
    S.status='145 units left and 120 down from restored baseline; inspect headset'
    local iconTranslation,iconScale=transform(S.icon)
    S.measured={translation=wanted,scale=scale,iconTranslation=iconTranslation,iconScale=iconScale,
        offset={X=S.offsetX,Y=S.offsetY},lastIconPin=S.lastIconPin}
end
uevr.sdk.callbacks.on_post_engine_tick(function()
    local ok,err=pcall(apply);if not ok then S.status=tostring(err) end
    if not S.stopped and S.ticks%120==0 then end
end)
pcall(function()uevr.sdk.callbacks.on_script_reset(S.restore)end)

end)(AC8Runtime.host('layout','ac8_velocity_alignment.lua'),AC8Runtime.json,AC8Runtime.log)
end

do
-- forward locator
(function(uevr,json,print)
do

local old=rawget(_G,'AC8_ForwardLocatorTest')
if old then old.stopped=true;if old.restore then old.restore() end end
local S={version=3,enabled=true,stopped=false,y=-600,ticks=0,status='waiting for locator widget'}
rawset(_G,'AC8_ForwardLocatorTest',S)
local function call(o,k,...)
    if o~=uevr.api and not AC8Runtime.isLiveObject(o)then return nil end
    if not o then return nil end
    local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function full(o)return call(o,'get_full_name')end
local function read(o)
    local ok,v=pcall(function()
        local p=o:get_property('FowardLocatorOffset')
        if type(p.X)~='number' or type(p.Y)~='number' then return nil end
        return {X=p.X,Y=p.Y}
    end)
    if ok then return v end
end
local function same(a,b)return a and b and math.abs(a.X-b.X)<.001 and math.abs(a.Y-b.Y)<.001 end
local function set(o,p)
    pcall(function()local v=o:get_property('FowardLocatorOffset');v.X=p.X;v.Y=p.Y end)
    if not same(read(o),p) then pcall(function()o:set_property('FowardLocatorOffset',p)end) end
    return same(read(o),p)
end

function S.restore()
    if S.widget and full(S.widget)==S.name and S.original then
        local current=read(S.widget)
        if same(current,S.applied) and not set(S.widget,S.original) then return false end
    end
    S.widget=nil;S.name=nil;S.original=nil;S.applied=nil;S.verified=false
    return true
end
local function discard()S.widget=nil;S.name=nil;S.original=nil;S.applied=nil;S.verified=false end
local function apply()
    if S.stopped then return end
    S.ticks=S.ticks+1
    local pc=call(uevr.api,'get_player_controller',0);local hud=call(pc,'GetHUD');local hn=full(hud) or ''
    local ci=rawget(_G,'AC8_CinematicIntent')
    if not hn:match('^LiveMainHUDParent4K_C ')then discard();S.status='inactive';return end
    if not S.enabled or (ci and ci.cameraLocked) then
        S.restore();S.status='inactive';return
    end
    local canvas=call(hud,'get_property','DynamicCanvas')
    local cn=full(canvas)
    if cn~=S.canvasName then discard();S.canvasName=cn end
    if S.widget and full(S.widget)~=S.name then discard()end
    if not S.widget then
        for i=0,math.min(call(canvas,'GetChildrenCount') or 0,64)-1 do
            local w=call(canvas,'GetChildAt',i);local n=full(w) or ''
            if n:match('^WBP_HUD_DynamicWidget_Parts_Locator_000_C ') and n:match('%.WBP_LocatorWidget$') then
                local initial=read(w)
                if initial then S.widget=w;S.name=n;S.original=initial;break end
            end
        end
    end
    if not S.widget then S.status='locator widget unavailable';return end
    local wanted={X=S.original.X,Y=S.original.Y+S.y}
    S.verified=set(S.widget,wanted)
    if S.verified then S.applied=wanted;S.status='forward arrow correction applied; user confirmed position'
    else
        S.enabled=false
        local restored=set(S.widget,S.original)
        S.status=restored and 'write unavailable; original restored' or 'write unavailable; restoration needs checking'
        if restored then S.restore() end
    end
end
uevr.sdk.callbacks.on_pre_viewport_client_draw(function()
    local ok,err=pcall(apply)
    if not ok then S.enabled=false;S.restore();S.status=tostring(err) end
    if not S.stopped and (S.ticks==1 or S.ticks%120==0) then  end
end)
pcall(function()uevr.sdk.callbacks.on_script_reset(S.restore)end)

end

end)(AC8Runtime.host('layout','forward_locator.lua'),AC8Runtime.json,AC8Runtime.log)
end

-- Fixed HUD-container adjustments. No steady-state geometry inspection.
do
local R=AC8Runtime;local host=R.host('layout','fixed arrow and wingman status placement')
local S={version=61,epoch=-1,x=-180,scale=.96,nextControls=0,attempts=0,writes=0,failures=0};R.offscreenLocatorMargin=S
local W={version=61,gap=24};R.wingmanSelector=W;R.wingmanStatusLayout=W
local function call(o,k,...)if not o or(o~=uevr.api and not R.isLiveObject(o))then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function full(o)return call(o,'get_full_name')end
local function xy(v)local ok,x,y=pcall(function()return v.X,v.Y end);if ok and type(x)=='number'and type(y)=='number'and x==x and y==y then return{X=x,Y=y}end end
local function same(a,b)return a and b and math.abs(a.X-b.X)<.01 and math.abs(a.Y-b.Y)<.01 end
local function translation(o)if not R.isLiveObject(o)then return end;local ok,v=pcall(function()return o:get_property('RenderTransform').Translation end);return ok and xy(v)end
local function put(o,v)call(o,'SetRenderTranslation',v);return same(translation(o),v)end
local function scale(o)local ok,v=pcall(function()return o:get_property('RenderTransform').Scale end);return ok and xy(v)end
local function pivot(o)return xy(call(o,'GetRenderTransformPivot')or call(o,'get_property','RenderTransformPivot'))end
local function putScale(o,v)call(o,'SetRenderScale',v);return same(scale(o),v)end

local function parent(o)
 local p=call(o,'GetParent');if p then return p end
 local outer=call(o,'get_outer');if(full(outer)or''):match('^WidgetTree ')then return call(outer,'get_outer')end
end
local slate=call(call(uevr.api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary'),'get_class_default_object')
local function geo(o)return call(o,'GetPaintSpaceGeometry')or call(o,'GetCachedGeometry')end
local function point(g,p)return xy(call(slate,'LocalToAbsolute',g,p))end
local function rect(o)
 local g=geo(o);local size=xy(call(slate,'GetLocalSize',g));if not size or size.X<=0 or size.Y<=0 then return end
 local a=point(g,{X=0,Y=0});local b=point(g,size);if not a or not b then return end
 return{math.min(a.X,b.X),math.min(a.Y,b.Y),math.max(a.X,b.X),math.max(a.Y,b.Y)}
end
local function restore(row)
 if row.widget and R.isLiveObject(row.widget)and full(row.widget)==row.name and same(translation(row.widget),row.last)then put(row.widget,row.original)end
 if row.widget and R.isLiveObject(row.widget)then
  if row.originalScale and same(scale(row.widget),row.lastScale)then putScale(row.widget,row.originalScale)end
  if row.originalPivot and same(pivot(row.widget),row.lastPivot)then call(row.widget,'SetRenderTransformPivot',row.originalPivot)end
 end
 row.widget=nil;row.name=nil;row.last=nil;row.applied=false
end
local function discard(row)row.widget=nil;row.name=nil;row.last=nil;row.original=nil;row.originalScale=nil;row.originalPivot=nil;row.lastScale=nil;row.lastPivot=nil;row.applied=false end
local function findWidgets()
 local c=R.context;local prefix=(c.rootName or''):match('^%S+ (.+)$');if not prefix then return end
 -- These non-variable Blueprint tree nodes are not UProperties on HudWidget.
 local cls=call(uevr.api,'find_uobject','Class /Script/UMG.CanvasPanel')
 for _,o in ipairs(call(cls,'get_objects_matching',false)or{})do
  local n=full(o)or''
  if n:find(' '..prefix..'.',1,true)then
   if not S.widget and n:match('%.LowestPriorityDynamicDrawCanvas$')then S.widget=o;S.name=n;S.canvas=n;S.original=translation(o);S.originalScale=scale(o);S.originalPivot=pivot(o)end
   if not W.widget and n:find('.WBP_HUD_Command_Wingman_000.',1,true)and n:match('%.Command_S$')then W.widget=o;W.name=n;W.original=translation(o)end
  end
 end
end
local function placeStatus()
 if W.applied or not W.widget or not W.original then return end
 local refs=R.hudLayoutRefs;local radar=rect(refs and refs.radar);if not radar then W.status='waiting for radar paint';return end
 local content=rect(W.widget)
 if not content then
  -- The zero-size outer canvas may have painted icon children extending outside.
  local cls=call(uevr.api,'find_uobject','Class /Script/UMG.Widget')
  for _,o in ipairs(call(cls,'get_objects_matching',false)or{})do
   local n=full(o)or''
   if n:find('.WBP_HUD_Command_Wingman_000.',1,true)and(n:match('^Image ')or n:match('^TextBlock ')or n:match('^LocalizeTextBlock '))then
    local p=o
    for _=1,16 do
     p=parent(p);local pn=full(p);if not pn then break end
     if pn==W.name then
      local b=rect(o);if b then
       if not content then content=b else content={math.min(content[1],b[1]),math.min(content[2],b[2]),math.max(content[3],b[3]),math.max(content[4],b[4])}end
      end;break
     end
    end
   end
  end
 end
 if not content then W.status='status icon not painted; no guessed position';return end
 local pg=geo(parent(W.widget));local a=point(pg,{X=0,Y=0});local b=point(pg,{X=1,Y=1})
 if not a or not b or b.X<=a.X or b.Y<=a.Y then W.status='status parent geometry unavailable';return end
 local current=translation(W.widget);if not current then return end
 local wanted={X=current.X+(radar[1]-content[1])/(b.X-a.X),Y=current.Y+(radar[2]-content[4])/(b.Y-a.Y)-W.gap}
 if put(W.widget,wanted)then W.last=wanted;W.applied=true;W.status='small green Command_S status above radar, left aligned'
 else W.status='status translation readback failed'end
 W.radarBounds=radar;W.contentBounds=content
end


host.sdk.callbacks.on_post_engine_tick(function()
 local c=R.context
 if not c.flight then discard(S);discard(W);S.epoch=-1;return end
 if c.epoch~=S.epoch then
  discard(S);discard(W);S.epoch=c.epoch;S.attempts=0;S.nextAttempt=0;S.nextControls=0;W.status='waiting for status icon'
  W.enabled=false -- Initial placement precedes painted radar geometry availability
 end

 if R.tick>=S.nextControls then
  S.nextControls=R.tick+30;local control=R.read('ac8_offscreen_group_controls.json')or{}
  local x=tonumber(control.offsetX)or -180;local factor=tonumber(control.scale)or .96
  if x~=x or x< -400 or x>0 then x=-180 end
  if factor~=factor or factor<.8 or factor>1 then factor=.96 end
  if control.enabled==false then x=-160;factor=1 end
  if x~=S.x or factor~=S.scale then S.x=x;S.scale=factor;S.applied=false;S.attempts=0;S.nextAttempt=0 end
 end
 if S.applied and(W.applied or not W.enabled)then return end
 -- At most eight initialization attempts; steady state is a cached early exit.
 if S.attempts>=8 or R.tick<(S.nextAttempt or 0)then return end
 S.attempts=S.attempts+1;S.nextAttempt=R.tick+60
 if not S.widget or(W.enabled and not W.widget)then findWidgets()end
 if not S.applied and S.widget and S.original and S.originalScale and S.originalPivot then
  local wanted={X=S.original.X+S.x,Y=S.original.Y}
  local wantedScale={X=S.originalScale.X*S.scale,Y=S.originalScale.Y*S.scale}
  local wantedPivot={X=.5,Y=.5};call(S.widget,'SetRenderTransformPivot',wantedPivot)
  if put(S.widget,wanted)and putScale(S.widget,wantedScale)and same(pivot(S.widget),wantedPivot)then
   S.last=wanted;S.lastScale=wantedScale;S.lastPivot=wantedPivot;S.applied=true;S.writes=S.writes+1;S.status='off-screen canvas centered scale and left margin applied'
  else S.failures=S.failures+1;S.status='container setter readback failed'end
 end
 if W.enabled then placeStatus()end
 
end)
pcall(function()host.sdk.callbacks.on_script_reset(function()restore(S);restore(W)end)end)
end

-- center the captured shared ClientStatusIconParent loading indicator
-- widget. Preserve animation, content, scale, full-screen loading background.
do
local R=AC8Runtime;local host=R.host('layout','center loading icon')
local S={version=71,nextDiscover=0,rows={},writes=0,report={version=70,status='waiting for loading icon'}};R.loadingIconCenter=S
local function call(o,k,...)
 if not o or(o~=uevr.api and not R.isLiveObject(o))then return end
 local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function xy(v)
 local x,y=field(v,'X'),field(v,'Y');if type(x)=='number'and type(y)=='number'and x==x and y==y then return{X=x,Y=y}end
end
local function full(o)return call(o,'get_full_name')end
local function anchors(v)
 local a,b=xy(field(v,'Minimum')),xy(field(v,'Maximum'));if a and b then return{Minimum=a,Maximum=b}end
end
local function same(a,b)return a and b and math.abs(a.X-b.X)<.01 and math.abs(a.Y-b.Y)<.01 end
local function sameAnchors(a,b)return a and b and same(a.Minimum,b.Minimum)and same(a.Maximum,b.Maximum)end
local middle={X=.5,Y=.5};local centered={Minimum=middle,Maximum=middle};local zero={X=0,Y=0}
local slate=call(uevr.api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary');slate=call(slate,'get_class_default_object')
local function rect(o)
 local g=call(o,'GetPaintSpaceGeometry')or call(o,'GetCachedGeometry');local size=xy(call(slate,'GetLocalSize',g))
 if not size or size.X<=0 or size.Y<=0 then return end
 local a=xy(call(slate,'LocalToAbsolute',g,zero));local b=xy(call(slate,'LocalToAbsolute',g,size))
 if not a or not b then return end
 return{math.min(a.X,b.X),math.min(a.Y,b.Y),math.max(a.X,b.X),math.max(a.Y,b.Y)}
end
local function slotState(slot)
 return{anchors=anchors(call(slot,'GetAnchors')),alignment=xy(call(slot,'GetAlignment')),position=xy(call(slot,'GetPosition'))}
end
local function put(slot,a,alignment,position)
 call(slot,'SetAnchors',a);call(slot,'SetAlignment',alignment);call(slot,'SetPosition',position)
 local got=slotState(slot);return sameAnchors(got.anchors,a)and same(got.alignment,alignment)and same(got.position,position)
end
local function qualified(o)
 local slot=call(o,'get_property','Slot');if not(full(slot)or''):match('^CanvasPanelSlot ')then return end
 local old=slotState(slot);local a=old.anchors
 if not a or not old.alignment or not old.position then return end
 -- Fixed bottom-right anchors identify the authored corner container without
 -- moving the full-screen loading panel or guessing from its instance name.
 local known=full(o)or''
 if known:find('WBP_Loading_Root_000_C_',1,true)and known:find('.ClientStatusIconParent.',1,true)and known:match('%.HorizontalBox_61$')then return slot,old,rect(o)end
 if not same(a.Minimum,a.Maximum)or a.Minimum.X<.75 or a.Minimum.Y<.75 then return end
 local name=full(o)or''
 if name:find('WBP_Loading_Root_000_C_',1,true)and(name:match('%.ClientStatusIconParent$')or name:match('%.LoadingIcon$'))then return slot,old,rect(o)end
 local parent=call(o,'GetParent');local pr,wr=rect(parent),rect(o)
 if not pr or not wr then return end
 local pw,ph=pr[3]-pr[1],pr[4]-pr[2];local ww,wh=wr[3]-wr[1],wr[4]-wr[2]
 if pw<=0 or ph<=0 or ww<=0 or wh<=0 or ww>pw*.35 or wh>ph*.35 then return end
 local cx,cy=(wr[1]+wr[3])/2,(wr[2]+wr[4])/2
 if cx<pr[1]+pw*.65 or cy<pr[2]+ph*.65 then return end
 return slot,old,wr
end
local function iconContainer(owner)
 local queue={owner};local seen={};local index=1
 local tree=call(owner,'get_property','WidgetTree');local root=call(tree,'get_property','RootWidget')or call(owner,'GetRootWidget')
 if root then queue[#queue+1]=root end
 while index<=#queue and index<=64 do
  local w=queue[index];index=index+1
  if w and not seen[w]then
   seen[w]=true;local slot,old,bounds=qualified(w)
   if slot then return w,slot,old,bounds end
   local count=call(w,'GetChildrenCount')
   if type(count)=='number'then for i=0,math.min(count,32)-1 do if #queue<64 then queue[#queue+1]=call(w,'GetChildAt',i)end end end
   local content=call(w,'GetContent');if content and #queue<64 then queue[#queue+1]=content end
  end
 end
end
local function updateReport(status)
 S.report={version=71,status=status,writes=S.writes,rows={}}
 for _,row in pairs(S.rows)do S.report.rows[#S.report.rows+1]={owner=row.name,container=row.containerName,slot=row.slotName,applied=row.applied,original=row.original,beforeBounds=row.beforeBounds}end
end
local function apply(row)
 if row.applied then return end
 local w,slot,old,bounds=iconContainer(row.owner)
 if not w then updateReport('waiting for the captured corner status container');return end
 row.container=w;row.containerName=full(w);row.slot=slot;row.slotName=full(slot);row.original=old;row.beforeBounds=bounds
 if put(slot,centered,middle,zero)then row.applied=true;S.writes=S.writes+1;updateReport('loading icon centered')
 else put(slot,old.anchors,old.alignment,old.position);updateReport('placement unavailable; original restored')end
end
host.sdk.callbacks.on_post_engine_tick(function()
 -- Class-specific tracked discovery every 60 ticks. Applied containers are cached;
 -- there is no steady-state geometry polling or all-widget scan.
 if S.epoch~=R.context.epoch then S.epoch=R.context.epoch;S.nextDiscover=R.tick end
 for o,row in pairs(S.rows)do
  if not R.isLiveObject(o)or(row.slot and not R.isLiveObject(row.slot))then S.rows[o]=nil
  elseif not row.applied and R.tick%4==0 then apply(row)end
 end
 if R.tick<S.nextDiscover then return end;S.nextDiscover=R.tick+60
 S.class=S.class or call(uevr.api,'find_uobject','Class /Script/Live.LiveLoadingClientStatusIconParentWidget')
 local found=false
 for i,owner in ipairs(call(S.class,'get_objects_matching',false)or{})do
  if i>16 then break end
  local name=full(owner)or''
  if name:find('/Engine/Transient.',1,true)then
   found=true;local row=S.rows[owner]or{owner=owner,name=name};S.rows[owner]=row;apply(row)
  end
 end
 if not found then updateReport('waiting for loading icon')end
end)
function S.inventory()
 local result={}
 for _,row in pairs(S.rows)do
  local owner=row.owner
  if R.isLiveObject(owner)then
   local nodes={owner};local tree=call(owner,'get_property','WidgetTree');local root=call(tree,'get_property','RootWidget')
   if root then nodes[#nodes+1]=root end
   local index,seen=1,{}
   while index<=#nodes and index<=32 do
    local w=nodes[index];index=index+1
    if w and not seen[w]then
     seen[w]=true;local slot=call(w,'get_property','Slot')
     result[#result+1]={name=full(w),parent=full(call(w,'GetParent')),slot=full(slot),slotState=slotState(slot),geometry=rect(w),visibility=call(w,'GetVisibility'),opacity=call(w,'GetRenderOpacity')}
     for i=0,math.min(call(w,'GetChildrenCount')or 0,16)-1 do if #nodes<32 then nodes[#nodes+1]=call(w,'GetChildAt',i)end end
     local content=call(w,'GetContent');if content and #nodes<32 then nodes[#nodes+1]=content end
    end
   end
  end
 end
 return result
end
host.sdk.callbacks.on_script_reset(function()
 for _,row in pairs(S.rows)do
  if row.applied and R.isLiveObject(row.slot)then
   local current=slotState(row.slot)
   if sameAnchors(current.anchors,centered)and same(current.alignment,middle)and same(current.position,zero)then
    put(row.slot,row.original.anchors,row.original.alignment,row.original.position)
   end
  end
 end
 S.rows={}
end)
end

-- final accepted bomb calibration. No key capture or telemetry.
do
local R=AC8Runtime;local host=R.host('layout','accepted bomb projection')
local cfg=R.read('ac8_bomb_landing_controls.json')or{};local v=tonumber(cfg.fovAdjustmentDegrees)or 9
if v~=v or v< -40 or v>40 then v=9 end
local last
host.sdk.callbacks.on_post_engine_tick(function()
 local packet=(cfg.enabled~=false and'1'or'0')..'|'..tostring(v)..'|0|'..(R.context.flight and'1'or'0')
 if packet~=last then uevr.api:dispatch_custom_event('AC8_BombProjectionControls',packet);last=packet end
end)
host.sdk.callbacks.on_script_reset(function()uevr.api:dispatch_custom_event('AC8_BombProjectionControls','0|0|0|0')end)
end

-- refresh the velocity-icon origin attachment every engine frame.
-- The shared line/circle FOV calibration below remains independent of the origin.
do
local R=AC8Runtime;local host=R.host('layout','bomb velocity origin anchor')
local S={version=73,epoch=-1,nextDiscover=0};R.bombLineAnchor=S
local function call(o,k,...)
 if o~=uevr.api and not R.isLiveObject(o)then return end
 local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function xy(v)
 local x,y=field(v,'X'),field(v,'Y')
 if type(x)=='number'and type(y)=='number'and x==x and y==y and math.abs(x)<1e7 and math.abs(y)<1e7 then return{X=x,Y=y}end
end
local function disable(reason)
 if S.packet then uevr.api:dispatch_custom_event('AC8_BombLineAnchor','0|0|0|0|0')end
 S.packet=nil;S.status=reason
end
local function discover()
 local root=R.context.root;if not R.isLiveObject(root)then return end
 local alignment=rawget(_G,'AC8_VelocityAlignment')
 local icon=alignment and alignment.icon
 local rootPath=(R.context.rootName or''):match('^%S+ (.+)$')
 if not R.isLiveObject(icon)then
  local persistent=call(root,'get_property','WBP_ChroniclePersistent')
  icon=call(persistent,'get_property','VelocityIcon')
 end
 local iconName=call(icon,'get_full_name')or''
 if not R.isLiveObject(icon)or not rootPath or not iconName:find(' '..rootPath..'.',1,true)or not iconName:find('.WBP_ChroniclePersistent.',1,true)then return end
 local bomb=call(root,'get_property','WBP_ExplosivePredicationWidget')
 if not R.isLiveObject(bomb)then
  local cls=call(uevr.api,'find_uobject','Class /Script/Live.LiveExplosivePredicationWidget')
  for i,o in ipairs(call(cls,'get_objects_matching',false)or{})do
   if i>16 then break end
   if rootPath and(call(o,'get_full_name')or''):find(' '..rootPath..'.',1,true)and call(o,'get_property','CachedLiveHUD')==R.context.hud then bomb=o;break end
  end
 end
 if call(bomb,'get_property','CachedLiveHUD')~=R.context.hud then return end
 local canvas=call(bomb,'GetParent')
 if not R.isLiveObject(bomb)or not(call(canvas,'get_full_name')or''):match('^LiveDynamicDrawCanvas ')then return end
 S.icon=icon;S.iconName=iconName;S.bomb=bomb;S.canvas=canvas
 S.slate=call(call(uevr.api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary'),'get_class_default_object')
end
local function update()
 local c=R.context
 if S.epoch~=c.epoch then disable('waiting for current HUD');S.epoch=c.epoch;S.icon=nil;S.bomb=nil;S.canvas=nil;S.nextDiscover=0 end
 if not c.flight then disable('outside flight');return end
 if not R.isLiveObject(S.icon)or not R.isLiveObject(S.bomb)or not R.isLiveObject(S.canvas)or not R.isLiveObject(S.slate)then
  disable('waiting for velocity icon and bomb canvas')
  if R.tick<S.nextDiscover then return end;S.nextDiscover=R.tick+60;discover()
 end
 if not R.isLiveObject(S.icon)or not R.isLiveObject(S.bomb)or not R.isLiveObject(S.canvas)then return end
 local ig=call(S.icon,'GetPaintSpaceGeometry')or call(S.icon,'GetCachedGeometry')
 local cg=call(S.canvas,'GetPaintSpaceGeometry')or call(S.canvas,'GetCachedGeometry')
 if not ig or not cg then disable('waiting for painted geometry');return end
 local is=xy(call(S.slate,'GetLocalSize',ig));local cs=xy(call(S.slate,'GetLocalSize',cg))
 if not is or not cs or is.X<=0 or is.Y<=0 or cs.X<1000 or cs.Y<500 then disable('waiting for painted geometry');return end
 local absolute=xy(call(S.slate,'LocalToAbsolute',ig,{X=is.X/2,Y=is.Y/2}))
 local target=absolute and xy(call(S.slate,'AbsoluteToLocal',cg,absolute))
 local widget=call(S.bomb,'get_address');local canvas=call(S.canvas,'get_address')
 if not target or type(widget)~='number'or type(canvas)~='number'then disable('invalid origin geometry');return end
 if target.X<0 or target.Y<0 or target.X>cs.X or target.Y>cs.Y then disable('velocity icon outside canvas');return end
 local packet=string.format('1|%.0f|%.0f|%.8f|%.8f',widget,canvas,target.X,target.Y)
 if packet~=S.packet or R.tick-(S.sentAt or 0)>=12 then
  uevr.api:dispatch_custom_event('AC8_BombLineAnchor',packet);S.packet=packet;S.sentAt=R.tick
 end
 S.status='top follows velocity icon every frame; lower endpoint and circle share calibrated projection'
 S.target=target;S.absoluteCenter=absolute;S.canvasSize=cs
end
host.sdk.callbacks.on_post_engine_tick(update)
host.sdk.callbacks.on_script_reset(function()disable('script reset');uevr.api:dispatch_custom_event('AC8_BombProjectionControls','0|0|0|0')end)
end

-- Command_S stays on the stable HUD canvas. Cached radar geometry supplies
-- only Y; saved X remains independent of radar size and parent adjustments.
do
local R=AC8Runtime;local host=R.host('layout','cached wingman radar-top placement')
local S={version=81,epoch=-1,nextFind=0,nextRead=0,nextCheck=0,checks=0,writes=0,discoveries=0};R.wingmanStatusLayout=S;R.wingmanSelector=S
local file='ac8_wingman_status_controls.json'
local function call(o,k,...)
 if not o or(o~=uevr.api and not R.isLiveObject(o))then return end
 local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function full(o)return call(o,'get_full_name')end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function xy(v)local x,y=field(v,'X'),field(v,'Y');if type(x)=='number'and type(y)=='number'and x==x and y==y then return{X=x,Y=y}end end
local function same(a,b)return a and b and math.abs(a.X-b.X)<.1 and math.abs(a.Y-b.Y)<.1 end
local zero={X=0,Y=0}
local slate=call(call(uevr.api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary'),'get_class_default_object')
local function normalize(c)
 c=type(c)=='table'and c or{}
 local function number(k,default,lo,hi)local v=tonumber(c[k]);return v and v==v and v>=lo and v<=hi and v or default end
 return{enabled=c.enabled~=false,x=number('x',0,-1000,5000),y=number('y',1460,-1000,3200),width=number('width',440,1,2000),height=number('height',96,1,1000),liveAdjust=c.liveAdjust~=false,followRadarTop=c.followRadarTop~=false,radarGap=number('radarGap',24,0,300)}
end
local function slotLayout(slot)
 local offsets=call(slot,'GetOffsets');local anchors=call(slot,'GetAnchors');local alignment=xy(call(slot,'GetAlignment'))
 local min,max=xy(field(anchors,'Minimum')),xy(field(anchors,'Maximum'))
 local margin={Left=field(offsets,'Left'),Top=field(offsets,'Top'),Right=field(offsets,'Right'),Bottom=field(offsets,'Bottom')}
 if not alignment or not min or not max then return end
 for _,v in pairs(margin)do if type(v)~='number'then return end end
 return{offsets=margin,anchors={Minimum=min,Maximum=max},alignment=alignment,auto=call(slot,'GetAutoSize'),z=call(slot,'GetZOrder')}
end
local function restore()
 if S.reparented and R.isLiveObject(S.widget)and R.isLiveObject(S.originalParent)then
  call(S.widget,'RemoveFromParent');local slot=call(S.originalParent,'AddChildToCanvas',S.widget)
  if slot and S.originalLayout then
   local c=S.originalLayout;call(slot,'SetAnchors',c.anchors);call(slot,'SetOffsets',c.offsets);call(slot,'SetAlignment',c.alignment)
   call(slot,'SetAutoSize',c.auto);call(slot,'SetZOrder',c.z)
  end
  if S.original then call(S.widget,'SetRenderTranslation',S.original)end
 end
 S.widget=nil;S.canvas=nil;S.slot=nil;S.reparented=false;S.last=nil;S.radarState=nil
 S.small=nil;S.large=nil;S.expanded=nil;S.searchWidget=nil
end
local function find()
 local root = R.context.root
 local prefix=(R.context.rootName or''):match('^%S+ (.+)$');if not prefix or not R.isLiveObject(root) then return end
 S.discoveries=S.discoveries+1

 -- Direct targeted tree lookup
 local function findChild(w, target, maxd)
  local seen, found = {}, nil
  local function rec(node, d)
   if not node or found or d > maxd then return end
   local addr = tostring(node)
   if seen[addr] then return end
   seen[addr] = true
   local fn = full(node) or ''
   if fn:match(target) then found = node; return end
   local cc = call(node, 'GetChildrenCount') or 0
   for i = 0, cc - 1 do rec(call(node, 'GetChildAt', i), d + 1) end
   local wt = field(node, 'WidgetTree')
   if wt then rec(field(wt, 'RootWidget'), d + 1) end
  end
  rec(w, 0)
  return found
 end

 S.canvas = findChild(root, '%.AlwaysVisibleCanvas$', 8)
 S.widget = findChild(root, '%.WBP_HUD_Command_Wingman_000%..*%.Command_S$', 10)
 if S.widget then S.name = full(S.widget) end
 S.large = findChild(root, '%.MiniMapLayer%..*%.MiniMapCornerCanvas$', 10)
 S.expanded = findChild(root, '%.MiniMapLayer%..*%.MiniMapEnlargedCorners$', 10)
 local smallBorder = findChild(root, '%.MiniMapLayer%..*%.RadarBoundingArea$', 10)
 if smallBorder then
  S.small = smallBorder
  local tree = call(smallBorder, 'get_outer')
  if (full(tree) or ''):match('^WidgetTree ') then S.searchWidget = call(tree, 'get_outer') end
 end

 -- Fallback only if direct search failed
 if not S.canvas or not S.widget then
  local owned=R.ownedWidgets(R.context.root)
  local function objects(class)
   if owned then return owned end
   local cls=call(uevr.api,'find_uobject','Class /Script/UMG.'..class)
   return call(cls,'get_objects_matching',false)or{}
  end
  for _,o in ipairs(objects('CanvasPanel'))do
   local n=full(o)or''
   if n:match('^CanvasPanel ')and n:find(' '..prefix..'.',1,true)then
    if n:match('%.AlwaysVisibleCanvas$')then S.canvas=o end
    if n:find('.WBP_HUD_Command_Wingman_000.',1,true)and n:match('%.Command_S$')then S.widget=o;S.name=n end
    if n:find('.MiniMapLayer.',1,true)then
     if n:match('%.MiniMapCornerCanvas$')then S.large=o end
     if n:match('%.MiniMapEnlargedCorners$')then S.expanded=o end
    end
   end
  end
  for _,o in ipairs(objects('Border'))do local n=full(o)or''
   if n:match('^Border ')and n:find(' '..prefix..'.',1,true)and n:find('.MiniMapLayer.',1,true)and n:match('%.RadarBoundingArea$')then
    S.small=o;local tree=call(o,'get_outer');if(full(tree)or''):match('^WidgetTree ')then S.searchWidget=call(tree,'get_outer')end
   end
  end
 end
 if not S.canvas or not S.widget then S.status='waiting for Command_S and stable canvas';return end
 S.originalParent=call(S.widget,'GetParent');local oldSlot=call(S.widget,'get_property','Slot')
 S.originalLayout=slotLayout(oldSlot);S.original=xy(field(call(S.widget,'get_property','RenderTransform'),'Translation'))
 if not R.isLiveObject(S.originalParent)or not S.originalLayout or not S.original then S.widget=nil;S.status='original slot unavailable';return end
 S.reparented=true;call(S.widget,'RemoveFromParent')
 local slot=call(S.canvas,'AddChildToCanvas',S.widget)
 if not R.isLiveObject(slot)then restore();S.status='stable canvas attachment failed; original restored';return end
 S.slot=slot;S.reparented=true
 call(slot,'SetAnchors',{Minimum=zero,Maximum=zero});call(slot,'SetAlignment',zero);call(slot,'SetAutoSize',false)
 call(slot,'SetZOrder',S.originalLayout.z or 0);call(S.widget,'SetRenderTranslation',zero)
 S.status='Command_S attached to stable HUD canvas'
end
local function radarTop(c)
 if not c.followRadarTop then return end
 local visibility=call(S.expanded,'GetVisibility');local searchVisibility=call(S.searchWidget,'GetVisibility')
 local expanded=visibility==0 or visibility==3 or visibility==4 or searchVisibility==1 or searchVisibility==2
 local widget=expanded and S.large or S.small
 local g=call(widget,'GetPaintSpaceGeometry')or call(widget,'GetCachedGeometry')
 local cg=call(S.canvas,'GetPaintSpaceGeometry')or call(S.canvas,'GetCachedGeometry')
 local size=xy(call(slate,'GetLocalSize',g));local canvasSize=xy(call(slate,'GetLocalSize',cg))
 if not size or not canvasSize or size.X<1 or size.Y<1 or canvasSize.X<1 or canvasSize.Y<1 then return end
 local absolute=xy(call(slate,'LocalToAbsolute',g,zero));local top=absolute and xy(call(slate,'AbsoluteToLocal',cg,absolute))
 if not top or top.Y<0 or top.Y>canvasSize.Y or top.X< -1000 or top.X>canvasSize.X then return end
 S.radarState={mode=expanded and'expanded' or'small',expandedVisibility=visibility,searchVisibility=searchVisibility,name=full(widget),top=top,localSize=size}
 return top.Y-c.height-c.radarGap
end
local function apply(c)
 S.checks=S.checks+1
 local y=radarTop(c)or c.y;local wanted={X=c.x,Y=y};local size={X=c.width,Y=c.height}
 local position=xy(call(S.slot,'GetPosition'));local actualSize=xy(call(S.slot,'GetSize'))
 local translation=xy(field(call(S.widget,'get_property','RenderTransform'),'Translation'))
 if not same(position,wanted)then call(S.slot,'SetPosition',wanted);S.writes=S.writes+1 end
 if not same(actualSize,size)then call(S.slot,'SetSize',size);S.writes=S.writes+1 end
 if translation and not same(translation,zero)then call(S.widget,'SetRenderTranslation',zero);S.writes=S.writes+1 end
 S.last=wanted;S.actual=position;S.status=S.radarState and'fixed X; Y follows displayed radar top' or'fixed fallback position; radar geometry unavailable'
end
host.sdk.callbacks.on_post_engine_tick(function()
 local ctx=R.context
 if S.epoch~=ctx.epoch then restore();S.epoch=ctx.epoch;S.nextFind=0;S.nextRead=0;S.nextCheck=0 end
 if not ctx.flight then return end
 if R.tick>=S.nextRead then
  S.nextRead=R.tick+30
  if not S.cfg or S.cfg.liveAdjust then R.cache[file]=nil;S.cfg=normalize(R.read(file))end
 end
 if not S.cfg.enabled then if S.reparented then restore()end;return end
 if R.tick<S.nextCheck then return end;S.nextCheck=R.tick+3
 if not R.isLiveObject(S.widget)or not R.isLiveObject(S.slot)then
  if R.tick<S.nextFind then return end;S.nextFind=R.tick+60;find()
 end
 if S.reparented and R.isLiveObject(S.slot)then apply(S.cfg)end
end)
host.sdk.callbacks.on_script_reset(restore)
end

end

if registry.start then registry.start() end
