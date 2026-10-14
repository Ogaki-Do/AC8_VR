-- Shared lifetime checks, current HUD context and deterministic callback dispatch.
-- Configuration reads are cached; only recovery/configuration journals may be written.
-- All section factories must register before any module starts changing game state.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['core'], 'Duplicate AC8 VR section: core')
registry.sections['core'] = function(R)
-- AC8 utility services and inherited Flat2VR adaptations.
-- Inherited code is attributed in the sections below; original history is backed up.
local real=uevr;local realJSON=json
local R={version=94,tick=0,domains={},connected={},context={epoch=0},cache={},errors={},inheritedSetup={},layoutEnabled=false}
_G.AC8Runtime=R
local order={'presentation','layout','utility','intro'}
local function invoke(o,k,...)local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
-- UObjectHook tracks destruction; membership checks do not walk reflected fields.
local objectHook=rawget(_G,'UEVR_UObjectHook')or(real.types and real.types.UObjectHook)
local exists=objectHook and objectHook.exists
R.objectLifetimeCheckAvailable=type(exists)=='function'
if not R.objectLifetimeCheckAvailable then R.errors.lifetime='UObjectHook.exists unavailable; unsafe UObject access skipped' end
function R.isLiveObject(o)
 if not o or type(exists)~='function'then return false end
 local ok,alive=pcall(exists,o);return ok and alive==true
end
-- UObject calls require lifetime membership. SDK tables and returned geometry
-- structs use their own helpers; they must not be sent through this guard.
function R.objectCall(o,k,...)
 if not R.isLiveObject(o)then return nil end
 return invoke(o,k,...)
end
-- Shared discovery within one engine tick. Walk only the requested widget's
-- painted hierarchy, including nested UserWidget trees. Callers retain their
-- existing visibility, clipping and owner checks and their discovery cadence.
-- An unavailable root or incomplete walk returns nil for the legacy fallback.
local widgetWalk={}
function R.ownedWidgets(root)
 if widgetWalk.tick~=R.tick or widgetWalk.epoch~=R.context.epoch then
  widgetWalk={tick=R.tick,epoch=R.context.epoch,roots={}}
 end
 local name=R.objectCall(root,'get_full_name')
 if not name then return nil end
 local cached=widgetWalk.roots[name]
 if cached and cached.root==root then
  local alive=true
  for _,w in ipairs(cached.rows)do if not R.isLiveObject(w)then alive=false;break end end
  if alive then return cached.rows end
 end
 local tree=R.objectCall(root,'get_property','WidgetTree')
 local first=R.objectCall(tree,'get_property','RootWidget')
 if not R.isLiveObject(first)then return nil end
 local rows,queue,seen={},{root},{}
 local index=1
 while index<=#queue do
  if index>8192 then return nil end
  local w=queue[index];index=index+1
  local n=R.objectCall(w,'get_full_name')
  if not n then return nil end
  if not seen[n]then
   seen[n]=true;rows[#rows+1]=w
   local count=R.objectCall(w,'GetChildrenCount')
   if count~=nil then
    if type(count)~='number'or count<0 or count>4096 or count%1~=0 then return nil end
    for i=0,count-1 do
     local child=R.objectCall(w,'GetChildAt',i)
     if not R.isLiveObject(child)then return nil end
     queue[#queue+1]=child
    end
   end
   local wt=R.objectCall(w,'get_property','WidgetTree')
   if wt then
    local child=R.objectCall(wt,'get_property','RootWidget')
    if not R.isLiveObject(child)then return nil end
    queue[#queue+1]=child
   end
  end
 end
 widgetWalk.roots[name]={root=root,rows=rows}
 return rows
end
function R.contextTick(advance)
 if advance~=false then R.tick=R.tick+1 end
 if R.profileCount then R.profileCount('contextTick') end
 local pc=invoke(real.api,'get_player_controller',0)
 if not R.isLiveObject(pc)then pc=nil end
 local hud=invoke(pc,'GetHUD');if not R.isLiveObject(hud)then hud=nil end
 local root=invoke(hud,'get_property','HudWidget');if not R.isLiveObject(root)then root=nil end
 local hn=invoke(hud,'get_full_name') or '';local rn=invoke(root,'get_full_name') or ''
 local identity=hn..'|'..rn
 local identityChanged = (identity~=R.context.identity)
 if identityChanged then R.context.epoch=R.context.epoch+1;R.context.changedAt=R.tick;R.context.identity=identity end
 R.context.pc=pc;R.context.hud=hud;R.context.root=root;R.context.hudName=hn;R.context.rootName=rn;R.context.flight=hn:match('^LiveMainHUDParent4K_C ')~=nil

 if (R.tick % 30 == 0 or identityChanged) then
  if R.applyActiveCameraOffset then
   local curPlane = R.getCurrentPlaneName and R.getCurrentPlaneName()
   if curPlane ~= R.context.planeName or identityChanged then
    R.context.planeName = curPlane
    pcall(R.applyActiveCameraOffset)
   end
  end
  if R.applyMultiRadar and R.customHUDConfig and R.customHUDConfig.multiRadar and R.customHUDConfig.multiRadar.enabled then
   pcall(R.applyMultiRadar)
  end
 end

 if R.updateInstantAwakeCycle then
  R.updateInstantAwakeCycle()
 end
end
function R.connect(key)
 if R.connected[key]then return end;R.connected[key]=true
 real.sdk.callbacks[key](function(...)
  if key=='on_pre_engine_tick'then
   R.contextTick()
   if R.tickProfiler then R.tickProfiler() end
  end
  for _,domain in ipairs(order)do
   local rows=(domain~='layout'or R.layoutEnabled)and R.domains[domain]and R.domains[domain][key]
   for _,row in ipairs(rows or {})do
    local ok,err=pcall(row.fn,...)
    if not ok then R.errors[row.name]=tostring(err)end
   end
  end
 end)
end
function R.host(domain,name)
 R.domains[domain]=R.domains[domain]or {}
 local callbacks=setmetatable({},{__index=function(_,key)return function(fn)
  local d=R.domains[domain];d[key]=d[key]or {};d[key][#d[key]+1]={fn=fn,name=name..':'..key};R.connect(key)
 end end})
 return setmetatable({sdk=setmetatable({callbacks=callbacks},{__index=real.sdk})},{__index=real})
end
function R.read(name)
 local c=R.cache[name];if c and R.tick-c.tick<30 then return c.value end
 local ok,value=pcall(realJSON.load_file,name);R.cache[name]={tick=R.tick,value=ok and value or nil};return ok and value or nil
end
local journals={['ac8_cinematic_ui_restore.json']=true,['ac8_hangar_restore_v48.json']=true,['ac8_ladder.json']=true,['ac8_hud_layout_cache.json']=true,['data/CustomHUDPosition.json']=true,['CustomHUDPosition.json']=true}
R.json={load_file=R.read,dump_file=function(name,value,indent)
 if journals[name]then R.cache[name]=nil;return realJSON.dump_file(name,value,indent)end
end}
function R.log(_)end -- Legacy adapters receive a quiet logger; errors stay in R.errors.

-- Custom HUD and Cinematic configuration (P1 Full Integration)
local function ensureCustomHUDDefaults(cfg)
 cfg.version = cfg.version or 1
 if not cfg.cinematicPresentation then cfg.cinematicPresentation = { enabled = false } end
 if not cfg.hudElements then cfg.hudElements = {} end
 local he = cfg.hudElements
 if not he.pitchLadder then he.pitchLadder = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 } end
 if not he.radar then he.radar = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 } end
 if not he.aircraftInfo then he.aircraftInfo = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 } end
 if not he.drawCanvas then he.drawCanvas = { scale = 1.0, opacity = 1.0 } end
 if not he.locatorArrow then he.locatorArrow = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 } end
 if not he.wingman then he.wingman = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 } end
 if not cfg.cameraOffsets then
  cfg.cameraOffsets = { default = { forward = -18.0, right = 0.0, up = 5.0 }, planes = {} }
 end
 if not cfg.cameraOffsets.default then
  cfg.cameraOffsets.default = { forward = -18.0, right = 0.0, up = 5.0 }
 end
 if not cfg.cameraOffsets.planes then cfg.cameraOffsets.planes = {} end
 if not cfg.multiRadar then
  cfg.multiRadar = { enabled = false, mode = 'search', x = 0.40, y = 0.25, scale = 0.85, opacity = 0.95 }
 end
 if cfg.multiRadar.enabled == nil then cfg.multiRadar.enabled = false end
 if not cfg.multiRadar.mode then cfg.multiRadar.mode = 'search' end
 if cfg.multiRadar.x == nil then cfg.multiRadar.x = 0.40 end
 if cfg.multiRadar.y == nil then cfg.multiRadar.y = 0.25 end
 if cfg.multiRadar.scale == nil then cfg.multiRadar.scale = 0.85 end
 if cfg.multiRadar.opacity == nil then cfg.multiRadar.opacity = 0.95 end
 return cfg
end

local function loadCustomHUDConfig()
 local paths={'data/CustomHUDPosition.json','CustomHUDPosition.json'}
 for _,p in ipairs(paths)do
  local ok,data=pcall(function()return realJSON.load_file(p)end)
  if ok and type(data)=='table'then return ensureCustomHUDDefaults(data),p end
 end
 return ensureCustomHUDDefaults({}),'data/CustomHUDPosition.json'
end
R.customHUDConfig,R.customHUDConfigPath=loadCustomHUDConfig()

function R.isCinematicEnabled()
 local cfg=R.customHUDConfig and R.customHUDConfig.cinematicPresentation
 return cfg and cfg.enabled==true
end

local savePending = false
function R.saveCustomHUDConfig()
 if not R.customHUDConfig then return end
 local p=R.customHUDConfigPath or 'data/CustomHUDPosition.json'
 pcall(function()realJSON.dump_file(p,R.customHUDConfig,2)end)
 pcall(function()realJSON.dump_file('CustomHUDPosition.json',R.customHUDConfig,2)end)
 savePending = false
end

-- Base transforms storage for clean offset layering without feedback drift
local baseTransforms = {}
function R.applyHUDCustomElement(widgetKey, widget, cfg, hasPos)
 if not widget or not R.isLiveObject(widget) or not cfg then return end
 local n = R.objectCall(widget, 'get_full_name') or tostring(widgetKey)
 if not baseTransforms[n] then
  local rt = R.objectCall(widget, 'get_property', 'RenderTransform')
  local t = rt and R.objectCall(rt, 'get_property', 'Translation')
  local sc = rt and R.objectCall(rt, 'get_property', 'Scale')
  local base_x = (t and type(t.X) == 'number') and t.X or 0.0
  local base_y = (t and type(t.Y) == 'number') and t.Y or 0.0
  local base_scale = (sc and type(sc.X) == 'number') and sc.X or 1.0
  baseTransforms[n] = { x = base_x, y = base_y, scale = base_scale }
 end
 local base = baseTransforms[n]
 -- Screen normalized ratio: -1.0 .. +1.0 mapped to half-screen 960x540 px
 if hasPos ~= false then
  local final_x = base.x + ((cfg.x or 0.0) * 960.0)
  local final_y = base.y + ((cfg.y or 0.0) * 540.0)
  pcall(function() widget:SetRenderTranslation({ X = final_x, Y = final_y }) end)
 end
 local final_scale = base.scale * (cfg.scale or 1.0)
 pcall(function() widget:SetRenderScale({ X = final_scale, Y = final_scale }) end)
 if cfg.opacity and type(cfg.opacity) == 'number' then
  pcall(function() widget:SetRenderOpacity(cfg.opacity) end)
 end
end

function R.applyAllHUDCustomPositions()
 local refs = R.hudLayoutRefs
 if not refs then return end
 local he = R.customHUDConfig and R.customHUDConfig.hudElements
 if not he then return end

 -- 1. Pitch Ladder (Altimeter / Horizon)
 if refs.altimeter and he.pitchLadder then
  R.applyHUDCustomElement('pitchLadder', refs.altimeter, he.pitchLadder, true)
 end
 -- 2. Radar (MiniMap)
 if refs.radar and he.radar then
  R.applyHUDCustomElement('radar', refs.radar, he.radar, true)
 end
 -- 3. Aircraft Info (Weapons / HP)
 if refs.wtsc and he.aircraftInfo then
  R.applyHUDCustomElement('aircraftInfo', refs.wtsc, he.aircraftInfo, true)
 end
 -- 4. Draw Canvas (Main UI Boundary)
 if refs.maincv and he.drawCanvas then
  R.applyHUDCustomElement('drawCanvas', refs.maincv, he.drawCanvas, false)
 end
 -- 5. Offscreen Locator Arrow
 local locator = rawget(_G, 'AC8_OffscreenLocatorWidget') or (refs and refs.locator)
 if locator and he.locatorArrow then
  R.applyHUDCustomElement('locatorArrow', locator, he.locatorArrow, true)
 end
 -- 6. Wingman Command Formation
 local wingman = rawget(_G, 'AC8_WingmanCommandWidget') or (refs and refs.wingman)
 if wingman and he.wingman then
  R.applyHUDCustomElement('wingman', wingman, he.wingman, true)
 end

 -- 7. Multi-Radar / Secondary Map (P2)
 if R.applyMultiRadar then
  pcall(R.applyMultiRadar)
 end
end

-- Secondary Multi-Radar Management (P2)
R.secondaryRadarWidgets = nil
function R.findSecondaryRadarWidgets()
 local refs = R.hudLayoutRefs
 local root = (refs and refs.maincv) or (refs and refs.root) or R.context.root
 if not root or not R.isLiveObject(root) then return end
 local found = {}
 local seen = {}
 local function rec(w, d)
  if not w or d > 16 then return end
  local p = tostring(w)
  if seen[p] then return end
  seen[p] = true
  local n = R.objectCall(w, 'get_full_name') or ''
  local sn = n:match('([^.]+)$') or n
  if sn == 'MiniMapSearchWidget' or sn:find('MiniMapSearchWidget', 1, true) then found.search = w end
  if sn == 'MiniMapEnlargedWidget' or sn:find('MiniMapEnlargedWidget', 1, true) then found.enlarged = w end
  if sn == 'MiniMapWholeWidget' or sn:find('MiniMapWholeWidget', 1, true) then found.whole = w end
  if sn == 'MiniMapSearchCorners' or sn:find('MiniMapSearchCorners', 1, true) then found.corners = w end

  local count = R.objectCall(w, 'GetChildrenCount') or 0
  if type(count) == 'number' and count > 0 then
   for i = 0, count - 1 do
    local c = R.objectCall(w, 'GetChildAt', i)
    if c then rec(c, d + 1) end
   end
  end
  local wt = R.objectCall(w, 'get_property', 'WidgetTree')
  if wt then
   local rw = R.objectCall(wt, 'get_property', 'RootWidget')
   if rw then rec(rw, d + 1) end
  end
 end
 rec(root, 0)
 R.secondaryRadarWidgets = found
end

function R.applyMultiRadar()
 local mr = R.customHUDConfig and R.customHUDConfig.multiRadar
 if not mr then return end
 local widgets = R.secondaryRadarWidgets
 if not widgets or not widgets.search or not R.isLiveObject(widgets.search) then
  R.findSecondaryRadarWidgets()
  widgets = R.secondaryRadarWidgets
 end
 if not widgets then return end

 local mode = mr.mode or 'search'
 local targetWidget = (mode == 'enlarged' and widgets.enlarged)
    or (mode == 'whole' and widgets.whole)
    or widgets.search

 if mr.enabled then
  for k, w in pairs(widgets) do
   if k ~= 'corners' and w and R.isLiveObject(w) and w ~= targetWidget then
    pcall(function() w:SetVisibility(1) end) -- 1 = Collapsed
   end
  end
  if targetWidget and R.isLiveObject(targetWidget) then
   pcall(function()
    targetWidget:SetVisibility(0) -- 0 = Visible
    targetWidget:SetRenderOpacity(mr.opacity or 0.95)
    local tx = (mr.x or 0.40) * 960.0
    local ty = (mr.y or 0.25) * 540.0
    targetWidget:SetRenderTranslation({ X = tx, Y = ty })
    local sc = mr.scale or 0.85
    targetWidget:SetRenderScale({ X = sc, Y = sc })
   end)
  end
  if widgets.corners and R.isLiveObject(widgets.corners) and mode == 'search' then
   pcall(function()
    widgets.corners:SetVisibility(0)
    widgets.corners:SetRenderOpacity(mr.opacity or 0.95)
    local tx = (mr.x or 0.40) * 960.0
    local ty = (mr.y or 0.25) * 540.0
    widgets.corners:SetRenderTranslation({ X = tx, Y = ty })
    local sc = mr.scale or 0.85
    widgets.corners:SetRenderScale({ X = sc, Y = sc })
   end)
  end
 else
  for k, w in pairs(widgets) do
   if w and R.isLiveObject(w) then
    pcall(function() w:SetVisibility(1) end) -- 1 = Collapsed
   end
  end
 end
end

-- =========================================================================
-- Instant Awake: All-Elements Unlocker (P3)
-- =========================================================================
local instantCycleActive = false
local instantCycleFrame = 0

function R.triggerInstantAwake()
 instantCycleActive = true
 instantCycleFrame = 0
 print('[AC8-VR] Triggered Instant Awake sequence...')
end

function R.setAllHUDVisibility(hide)
 local visCode = hide and 1 or 4 -- 1 = Collapsed, 4 = SelfHitTestInvisible
 local refs = R.hudLayoutRefs
 local candidates = {}
 if refs and refs.root and R.isLiveObject(refs.root) then candidates[#candidates+1] = refs.root end
 if refs and refs.maincv and R.isLiveObject(refs.maincv) then candidates[#candidates+1] = refs.maincv end
 if R.context.root and R.isLiveObject(R.context.root) then candidates[#candidates+1] = R.context.root end

 if #candidates == 0 and real.api then
  local umg = real.api:find_uobject('Class /Script/UMG.Widget')
  if umg then
   local ok, objs = pcall(function() return umg:get_objects_matching(false) end)
   if ok and type(objs) == 'table' then
    for _, w in ipairs(objs) do
     local fn = R.objectCall(w, 'get_full_name') or ''
     if fn:find('/Engine/Transient', 1, true) and fn:find('MainFlight', 1, true) then
      candidates[#candidates+1] = w
     end
    end
   end
  end
 end

 for _, w in ipairs(candidates) do
  pcall(function() w:SetVisibility(visCode) end)
 end
end

function R.updateInstantAwakeCycle()
 if not instantCycleActive then return end
 instantCycleFrame = instantCycleFrame + 1
 if instantCycleFrame == 1 then
  R.setAllHUDVisibility(true)
 elseif instantCycleFrame >= 4 then
  R.setAllHUDVisibility(false)
  instantCycleActive = false
  instantCycleFrame = 0
  if R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
  print('[AC8-VR] Instant Awake complete! All HUD elements unlocked.')
 end
end

-- Camera Offset Application
function R.getCurrentPlaneName()
 local pc = R.context.pc
 local pawn = pc and R.objectCall(pc, 'get_property', 'AcknowledgedPawn') or R.context.pawn
 if not pawn and real.api then pawn = real.api:get_local_pawn(0) end
 if pawn then
  local n = R.objectCall(pawn, 'get_full_name') or ''
  local plane = n:match('BP_PlayerPlane_([%w_]+)_C')
  if plane then return plane end
  local short = n:match('([^.]+)$') or n
  if short:find('PlayerPlane', 1, true) then return short end
 end
 return nil
end

function R.applyActiveCameraOffset()
 local co = R.customHUDConfig and R.customHUDConfig.cameraOffsets
 if not co then return end
 local planeName = R.getCurrentPlaneName()
 local offset = (planeName and co.planes and co.planes[planeName]) or co.default
 if not offset then return end
 pcall(function()
  uevr.params.vr.set_mod_value('VR_CameraForwardOffset', tostring(offset.forward or 0.0))
  uevr.params.vr.set_mod_value('VR_CameraRightOffset', tostring(offset.right or 0.0))
  uevr.params.vr.set_mod_value('VR_CameraUpOffset', tostring(offset.up or 0.0))
 end)
end

-- Lightweight performance profiler
R.profiler={enabled=false,frames=0,counts={}}
function R.profileCount(tag)
 if not R.profiler.enabled then return end
 local c=R.profiler.counts;c[tag]=(c[tag]or 0)+1
end
function R.tickProfiler()
 if not R.profiler.enabled then return end
 R.profiler.frames=R.profiler.frames+1
 if R.profiler.frames>=60 then
  local parts={}
  for k,v in pairs(R.profiler.counts)do parts[#parts+1]=string.format('%s=%d',k,v)end
  print(string.format('[AC8-PROF] (60 frames) %s',table.concat(parts,' ')))
  R.profiler.counts={};R.profiler.frames=0
 end
end

-- Helper for slider with nudge buttons
local function renderRatioSliderWithNudge(ui, label, tableRef, key, minVal, maxVal, defaultVal, elemKey)
 local id = (elemKey or '') .. '_' .. key
 local cur = tableRef[key] or defaultVal
 local changed, newVal = ui.slider_float(label .. '##' .. id, cur, minVal, maxVal)
 if changed and newVal ~= nil then
  tableRef[key] = newVal
  R.saveCustomHUDConfig()
  R.applyAllHUDCustomPositions()
 end
 -- Nudge buttons (-0.01, -0.005, +0.005, +0.01)
 if ui.button and ui.same_line then
  if ui.button('-0.01##' .. id) then tableRef[key] = math.max(minVal, (tableRef[key] or defaultVal) - 0.01); R.saveCustomHUDConfig(); R.applyAllHUDCustomPositions() end
  ui.same_line()
  if ui.button('-0.005##' .. id) then tableRef[key] = math.max(minVal, (tableRef[key] or defaultVal) - 0.005); R.saveCustomHUDConfig(); R.applyAllHUDCustomPositions() end
  ui.same_line()
  if ui.button('+0.005##' .. id) then tableRef[key] = math.min(maxVal, (tableRef[key] or defaultVal) + 0.005); R.saveCustomHUDConfig(); R.applyAllHUDCustomPositions() end
  ui.same_line()
  if ui.button('+0.01##' .. id) then tableRef[key] = math.min(maxVal, (tableRef[key] or defaultVal) + 0.01); R.saveCustomHUDConfig(); R.applyAllHUDCustomPositions() end
 end
end

local function renderElementUI(ui, title, elemKey, hasPos)
 local he = R.customHUDConfig.hudElements
 local elem = he[elemKey]
 if not elem then return end
 if ui.tree_node and ui.tree_node(title) then
  if hasPos ~= false then
   renderRatioSliderWithNudge(ui, 'Pos X Ratio (-1.0 ~ 1.0)', elem, 'x', -1.0, 1.0, 0.0, elemKey)
   renderRatioSliderWithNudge(ui, 'Pos Y Ratio (-1.0 ~ 1.0)', elem, 'y', -1.0, 1.0, 0.0, elemKey)
  end
  local sChanged, sVal = ui.slider_float('Scale (0.2 ~ 3.0)##' .. elemKey, elem.scale or 1.0, 0.2, 3.0)
  if sChanged and sVal ~= nil then elem.scale = sVal; R.saveCustomHUDConfig(); R.applyAllHUDCustomPositions() end
  local oChanged, oVal = ui.slider_float('Opacity (0.0 ~ 1.0)##' .. elemKey, elem.opacity or 1.0, 0.0, 1.0)
  if oChanged and oVal ~= nil then elem.opacity = oVal; R.saveCustomHUDConfig(); R.applyAllHUDCustomPositions() end

  if ui.button and ui.button('Reset ' .. title .. ' to Defaults##' .. elemKey) then
   if hasPos ~= false then elem.x = 0.0; elem.y = 0.0 end
   elem.scale = 1.0
   elem.opacity = 1.0
   R.saveCustomHUDConfig()
   R.applyAllHUDCustomPositions()
   print('[AC8-VR] Reset ' .. title .. ' to defaults')
  end
  if ui.tree_pop then ui.tree_pop() end
 end
end

-- UEVR Script UI (ImGui)
pcall(function()
 real.sdk.callbacks.on_draw_ui(function()
  local ui=rawget(_G,'imgui')
  if not ui then return end

  -- =========================================================================
  -- SECTION 1: AC8 VR Master Settings
  -- =========================================================================
  if ui.tree_node and ui.tree_node('AC8 VR Master Settings') then
   local cp=R.customHUDConfig and R.customHUDConfig.cinematicPresentation
   local curEnabled=(cp and cp.enabled==true)
   if ui.checkbox then
    local changed,newVal=ui.checkbox('Enable Cinematic Presentation',curEnabled)
    if changed and newVal~=nil then
     if not R.customHUDConfig then R.customHUDConfig=ensureCustomHUDDefaults({}) end
     R.customHUDConfig.cinematicPresentation.enabled=newVal
     R.saveCustomHUDConfig()
     print(string.format('[AC8-VR] Cinematic Presentation set to: %s (Saved to CustomHUDPosition.json)',tostring(newVal)))
    end
   end
   if ui.text_colored then
    if curEnabled then
     ui.text_colored('Status: ACTIVE (Cutscenes & Hangar overrides ON)',0.2,1.0,0.2,1.0)
    else
     ui.text_colored('Status: DISABLED (Zero Overhead - Max Performance)',0.4,0.8,1.0,1.0)
    end
    ui.text_colored('(Requires Script Reload or Game Restart if changed)',0.7,0.7,0.7,1.0)
   elseif ui.text then
    ui.text(curEnabled and 'Status: ACTIVE' or 'Status: DISABLED (Zero Overhead)')
    ui.text('(Requires Script Reload or Game Restart if changed)')
   end
   if curEnabled and R.toggleCinematicMode and ui.button then
    if ui.button('Toggle 2D Mask / 3D Mode (Test)') then
     R.toggleCinematicMode()
     print('[AC8-VR] Cinematic mode toggled via ScriptUI button')
    end
   end

   if ui.separator then ui.separator() end
   if ui.checkbox then
    local pChanged,pVal=ui.checkbox('Enable Performance Profiler Log',R.profiler.enabled)
    if pChanged and pVal~=nil then
     R.profiler.enabled=pVal
     print(string.format('[AC8-PROF] Profiler %s',pVal and 'ENABLED' or 'DISABLED'))
    end
   end
   if ui.tree_pop then ui.tree_pop() end
  end

  -- =========================================================================
  -- SECTION 2: HUD Element Customizer (P1 Core Feature)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('HUD Element Customizer (P1 Position & Scale)') then
   if ui.text then
    ui.text('Positions are normalized screen ratios: (-1.0 = Left/Top, 0.0 = Center, +1.0 = Right/Bottom)')
    ui.text('Fine-tuning buttons nudge by +-0.005 / +-0.01. Auto-saves to data/CustomHUDPosition.json')
   end
   if ui.separator then ui.separator() end

   renderElementUI(ui, 'Pitch Ladder / Artificial Horizon (人工水平儀)', 'pitchLadder', true)
   renderElementUI(ui, 'Radar / MiniMap (レーダー)', 'radar', true)
   renderElementUI(ui, 'Aircraft Info (残弾数 / HP / 武装情報)', 'aircraftInfo', true)
   renderElementUI(ui, 'Draw Canvas (全体描画領域)', 'drawCanvas', false)
   renderElementUI(ui, 'Off-screen Locator Arrow (画面外矢印)', 'locatorArrow', true)
   renderElementUI(ui, 'Wingman Formation (編隊指示)', 'wingman', true)

   if ui.separator then ui.separator() end
   if ui.button and ui.button('>> Reset All HUD Elements to Factory Defaults <<') then
    local he = R.customHUDConfig.hudElements
    he.pitchLadder = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 }
    he.radar = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 }
    he.aircraftInfo = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 }
    he.drawCanvas = { scale = 1.0, opacity = 1.0 }
    he.locatorArrow = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 }
    he.wingman = { x = 0.0, y = 0.0, scale = 1.0, opacity = 1.0 }
    R.saveCustomHUDConfig()
    R.applyAllHUDCustomPositions()
    print('[AC8-VR] All HUD elements reset to factory defaults')
   end
   if ui.tree_pop then ui.tree_pop() end
  end

  -- =========================================================================
  -- SECTION 3: Cockpit Head / Camera Position (P1)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('Cockpit Head Position / Camera Offset (P1)') then
   local plane = R.getCurrentPlaneName()
   if ui.text then
    ui.text('Current Aircraft: ' .. (plane or 'Unknown / Outside Cockpit'))
   end

   local co = R.customHUDConfig.cameraOffsets
   local isPlaneSpecific = (plane and co.planes and co.planes[plane] ~= nil)
   if plane and ui.checkbox then
    local psChanged, psVal = ui.checkbox('Save specific offset for this plane (' .. plane .. ')', isPlaneSpecific)
    if psChanged and psVal ~= nil then
     if psVal then
      co.planes[plane] = {
       forward = co.default.forward or -18.0,
       right = co.default.right or 0.0,
       up = co.default.up or 5.0
      }
     else
      co.planes[plane] = nil
     end
     R.saveCustomHUDConfig()
     R.applyActiveCameraOffset()
    end
   end

   local activeTarget = (plane and isPlaneSpecific and co.planes[plane]) or co.default
   local fChanged, fVal = ui.slider_float('Forward Offset (前後 cm)', activeTarget.forward or 0.0, -100.0, 100.0)
   if fChanged and fVal ~= nil then activeTarget.forward = fVal; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
   if ui.button and ui.same_line then
    if ui.button('-1.0cm##f') then activeTarget.forward = (activeTarget.forward or 0) - 1.0; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('-0.2cm##f') then activeTarget.forward = (activeTarget.forward or 0) - 0.2; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+0.2cm##f') then activeTarget.forward = (activeTarget.forward or 0) + 0.2; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+1.0cm##f') then activeTarget.forward = (activeTarget.forward or 0) + 1.0; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
   end

   local rChanged, rVal = ui.slider_float('Right Offset (左右 cm)', activeTarget.right or 0.0, -50.0, 50.0)
   if rChanged and rVal ~= nil then activeTarget.right = rVal; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
   if ui.button and ui.same_line then
    if ui.button('-1.0cm##r') then activeTarget.right = (activeTarget.right or 0) - 1.0; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('-0.2cm##r') then activeTarget.right = (activeTarget.right or 0) - 0.2; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+0.2cm##r') then activeTarget.right = (activeTarget.right or 0) + 0.2; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+1.0cm##r') then activeTarget.right = (activeTarget.right or 0) + 1.0; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
   end

   local uChanged, uVal = ui.slider_float('Up Offset (上下 cm)', activeTarget.up or 0.0, -50.0, 50.0)
   if uChanged and uVal ~= nil then activeTarget.up = uVal; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
   if ui.button and ui.same_line then
    if ui.button('-1.0cm##u') then activeTarget.up = (activeTarget.up or 0) - 1.0; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('-0.2cm##u') then activeTarget.up = (activeTarget.up or 0) - 0.2; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+0.2cm##u') then activeTarget.up = (activeTarget.up or 0) + 0.2; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+1.0cm##u') then activeTarget.up = (activeTarget.up or 0) + 1.0; R.saveCustomHUDConfig(); R.applyActiveCameraOffset() end
   end

   if ui.button and ui.button('Reset Camera to Defaults (-18, 0, +5 cm)') then
    activeTarget.forward = -18.0
    activeTarget.right = 0.0
    activeTarget.up = 5.0
    R.saveCustomHUDConfig()
    R.applyActiveCameraOffset()
    print('[AC8-VR] Camera offsets reset to defaults')
   end
   if ui.tree_pop then ui.tree_pop() end
  end

  -- =========================================================================
  -- SECTION 4: Multi-Radar / Dual Map System (P2)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('Multi-Radar / Dual Map System (P2)') then
   local mr = R.customHUDConfig and R.customHUDConfig.multiRadar
   if mr then
    if ui.checkbox then
     local changed, newVal = ui.checkbox('Enable Multi-Radar (Dual Radar Display)', mr.enabled == true)
     if changed and newVal ~= nil then
      mr.enabled = newVal
      R.saveCustomHUDConfig()
      R.applyMultiRadar()
      print(string.format('[AC8-VR] Multi-Radar set to: %s', tostring(newVal)))
     end
    end

    if mr.enabled then
     if ui.text then
      ui.text('Simultaneously displays a secondary wide-range radar alongside combat radar.')
     end
     if ui.separator then ui.separator() end

     -- Mode selector (Search / Enlarged / Whole)
     if ui.text then ui.text('Secondary Map Mode: ' .. tostring(mr.mode or 'search')) end
     if ui.button and ui.same_line then
      if ui.button('Search (索敵広域)') then mr.mode = 'search'; R.saveCustomHUDConfig(); R.applyMultiRadar() end
      ui.same_line()
      if ui.button('Enlarged (拡大)') then mr.mode = 'enlarged'; R.saveCustomHUDConfig(); R.applyMultiRadar() end
      ui.same_line()
      if ui.button('Whole (全体マップ)') then mr.mode = 'whole'; R.saveCustomHUDConfig(); R.applyMultiRadar() end
     end

     renderRatioSliderWithNudge(ui, 'Secondary Pos X Ratio (-1.0 ~ 1.0)', mr, 'x', -1.0, 1.0, 0.40, 'mr')
     renderRatioSliderWithNudge(ui, 'Secondary Pos Y Ratio (-1.0 ~ 1.0)', mr, 'y', -1.0, 1.0, 0.25, 'mr')

     local sChanged, sVal = ui.slider_float('Secondary Scale (0.2 ~ 3.0)##mr', mr.scale or 0.85, 0.2, 3.0)
     if sChanged and sVal ~= nil then mr.scale = sVal; R.saveCustomHUDConfig(); R.applyMultiRadar() end

     local oChanged, oVal = ui.slider_float('Secondary Opacity (0.0 ~ 1.0)##mr', mr.opacity or 0.95, 0.0, 1.0)
     if oChanged and oVal ~= nil then mr.opacity = oVal; R.saveCustomHUDConfig(); R.applyMultiRadar() end

     if ui.button and ui.button('Reset Multi-Radar to Defaults##mr') then
      mr.mode = 'search'
      mr.x = 0.40
      mr.y = 0.25
      mr.scale = 0.85
      mr.opacity = 0.95
      R.saveCustomHUDConfig()
      R.applyMultiRadar()
      print('[AC8-VR] Multi-Radar reset to defaults')
     end
    end
   end
   if ui.tree_pop then ui.tree_pop() end
  end

  -- =========================================================================
  -- SECTION 5: Instant Awake & HUD Visibility (P3)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('Instant Awake & HUD Visibility (P3)') then
   if ui.text then
    ui.text('Toggles HUD visibility off and on for 4 frames to unlock all sleeping/hidden')
    ui.text('gauges, locator elements, and flight indicators at once.')
   end
   if ui.separator then ui.separator() end

   if ui.button and ui.button('>> Instant Awake (Unlock All Elements) <<') then
    R.triggerInstantAwake()
   end

   if ui.separator then ui.separator() end
   if ui.button and ui.same_line then
    if ui.button('Force Show HUD') then
     R.setAllHUDVisibility(false)
     if R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
    end
    ui.same_line()
    if ui.button('Force Hide HUD') then
     R.setAllHUDVisibility(true)
    end
   end
   if ui.tree_pop then ui.tree_pop() end
  end
 end)
end)

R.connect('on_pre_engine_tick')


end

-- Registering files in any order produces the explicit initialization order.
-- A failed initializer is never retried in-place: restart the script environment.
local required = {'core','cutscene_guard','inherited_hud','mission_loading','glow_lifecycle','target_labels','target_animation','target_pins','target_materials','hud_policy','tutorial_fill','pause_attachment','transitions','plane_camera','cinematic','hud_layout','startup_movies'}
registry.required = required
function registry.start()
 if registry.state == 'failed' or registry.state == 'starting' then return end
 if registry.state ~= 'ready' then
  local missing = {}
  for _, key in ipairs(required) do
   if not registry.sections[key] then missing[#missing+1] = key end
  end
  registry.missing = missing
  if #missing > 0 then return end
  registry.state = 'starting'
  for _, key in ipairs(required) do
   local ok, result = pcall(registry.sections[key], rawget(_G, 'AC8Runtime'))
   if not ok then
    registry.state = 'failed'; registry.error = key .. ': ' .. tostring(result)
    print('AC8 VR startup failed: ' .. registry.error)
    error(registry.error)
   end
   registry.completed[#registry.completed+1] = key
  end
  registry.state = 'ready'
 end

end

if registry.start then registry.start() end
