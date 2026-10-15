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

 if (R.tick % 30 == 0 or identityChanged) and R.applyActiveCameraOffset then
  local curPlane = R.getCurrentPlaneName and R.getCurrentPlaneName()
  if curPlane ~= R.context.planeName or identityChanged then
   R.context.planeName = curPlane
   pcall(R.applyActiveCameraOffset)
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

-- Helper for finding descendants by substring
local function findDescendantByName(root, targetName)
 if not root or not R.isLiveObject(root) then return nil end
 local found = nil
 local seen = {}
 local function rec(w, d)
  if not w or found or d > 16 then return end
  local p = tostring(w)
  if seen[p] then return end
  seen[p] = true
  local n = R.objectCall(w, 'get_full_name') or ''
  local sn = n:match('([^.]+)$') or n
  if sn == targetName or sn:find(targetName, 1, true) then
   found = w
   return
  end
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
 return found
end

-- Custom HUD and Cinematic configuration (Legacy TARGETS Compatible)
local function ensureCustomHUDDefaults(cfg)
 cfg.version = 2
 if not cfg.cinematicPresentation then cfg.cinematicPresentation = { enabled = false } end
 if not cfg.hudElements then cfg.hudElements = {} end
 local he = cfg.hudElements

 -- Backward compatibility migration
 if he.pitchLadder and not he.ladder then he.ladder = he.pitchLadder end
 if he.aircraftInfo and not he.info then he.info = he.aircraftInfo end
 if he.drawCanvas and not he.drawcanvas then he.drawcanvas = he.drawCanvas end

 if not he.ladder then he.ladder = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.heading then he.heading = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.whisky then he.whisky = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.radar then he.radar = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.info then he.info = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.score then he.score = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.locator then he.locator = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.drawcanvas then he.drawcanvas = { scale = 1.0, opacity = 0.95 } end

 if not cfg.cameraOffsets then
  cfg.cameraOffsets = { default = { forward = -18.0, right = 0.0, up = 5.0 }, planes = {} }
 end
 if not cfg.cameraOffsets.default then
  cfg.cameraOffsets.default = { forward = -18.0, right = 0.0, up = 5.0 }
 end
 if not cfg.cameraOffsets.planes then cfg.cameraOffsets.planes = {} end
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

function R.saveCustomHUDConfig()
 if not R.customHUDConfig then return end
 local p=R.customHUDConfigPath or 'data/CustomHUDPosition.json'
 pcall(function()realJSON.dump_file(p,R.customHUDConfig,2)end)
 pcall(function()realJSON.dump_file('CustomHUDPosition.json',R.customHUDConfig,2)end)
 print('[AC8-VR] Configuration saved to ' .. p)
end

function R.reloadCustomHUDConfig()
 R.customHUDConfig, R.customHUDConfigPath = loadCustomHUDConfig()
 if R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
 if R.applyActiveCameraOffset then pcall(R.applyActiveCameraOffset) end
 print('[AC8-VR] Configuration reloaded from ' .. tostring(R.customHUDConfigPath))
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

 -- 1. PitchLadder (Altimeter / PitchMeter)
 local ladderWidget = refs.altimeter or refs.wtsc
 if ladderWidget and he.ladder then
  R.applyHUDCustomElement('ladder', ladderWidget, he.ladder, true)
 end

 -- 1-1. Heading (Velocity / VelocityIcon)
 local headingWidget = refs.vicon or refs.vel
 if headingWidget and he.heading then
  R.applyHUDCustomElement('heading', headingWidget, he.heading, true)
 end

 -- 1-2. WhiskyMarkPanel
 if refs.whisky and he.whisky then
  R.applyHUDCustomElement('whisky', refs.whisky, he.whisky, true)
 end

 -- 2. Radar (MiniMap)
 if refs.radar and he.radar then
  R.applyHUDCustomElement('radar', refs.radar, he.radar, true)
 end
 if refs.radarList and type(refs.radarList) == 'table' and he.radar then
  for _, rw in ipairs(refs.radarList) do
   if rw and rw ~= refs.radar then
    R.applyHUDCustomElement('radarExtra', rw, he.radar, true)
   end
  end
 end

 -- 3. AircraftInfo (WBP_PlayerStateWidget / PlaneCanvas)
 local infoWidget = refs.info
 if not infoWidget or not R.isLiveObject(infoWidget) then
  local root = refs.root or (R.context and R.context.root)
  infoWidget = findDescendantByName(root, 'WBP_PlayerStateWidget') or findDescendantByName(root, 'PlaneCanvas') or findDescendantByName(root, 'PlayerStatus')
  refs.info = infoWidget
 end
 if infoWidget and he.info then
  R.applyHUDCustomElement('info', infoWidget, he.info, true)
 end

 -- 4. Score / MissionInfo (CampaignInfo)
 local scoreWidget = refs.score or refs.campaign
 if not scoreWidget or not R.isLiveObject(scoreWidget) then
  local root = refs.root or (R.context and R.context.root)
  scoreWidget = findDescendantByName(root, 'CampaignInfo') or findDescendantByName(root, 'WBP_HUD_SubWidgets_Parts_CampaignInfo')
  refs.score = scoreWidget
 end
 if scoreWidget and he.score then
  R.applyHUDCustomElement('score', scoreWidget, he.score, true)
 end

 -- 5. Draw canvas (LowestPriorityDynamicDrawCanvas / MainCanvas)
 if refs.maincv and he.drawcanvas then
  R.applyHUDCustomElement('drawcanvas', refs.maincv, he.drawcanvas, false)
 end
end

-- =========================================================================
-- Emergency: Force Show ALL HUD (4-frame dormant elements unlocker)
-- =========================================================================
local instantCycleActive = false
local instantCycleFrame = 0

function R.triggerInstantAwake()
 instantCycleActive = true
 instantCycleFrame = 0
 print('[AC8-VR] Emergency: Force Show ALL HUD cycle triggered...')
end

local function setAllHUDVisibilityCode(visCode)
 if not real.api then return end
 local umg = real.api:find_uobject('Class /Script/UMG.Widget')
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

function R.updateInstantAwakeCycle()
 if not instantCycleActive then return end
 instantCycleFrame = instantCycleFrame + 1
 if instantCycleFrame == 1 then
  -- Frame 1: Collapse all MainFlight widgets to clear stale engine state
  setAllHUDVisibilityCode(1)
 elseif instantCycleFrame >= 4 then
  -- Frame 4: Restore SelfHitTestInvisible (wake up all dormant HUD elements!)
  setAllHUDVisibilityCode(4)
  instantCycleActive = false
  instantCycleFrame = 0
  if R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
  print('[AC8-VR] Emergency: Force Show ALL HUD complete! All dormant elements awakened.')
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

-- =========================================================================
-- Stepped Sliders with [+] / [-] buttons (Old ac8_ladder_fix_v19 compliant)
-- =========================================================================
local function renderSteppedSlider(ui, label, tableRef, key, min_v, max_v, step, id)
 local cur = (tableRef and type(tableRef[key]) == 'number') and tableRef[key] or 0.0
 local changed = false
 if ui.button and ui.button(' - ##dec_' .. id) then
  cur = math.max(min_v, cur - step)
  changed = true
 end
 if ui.same_line then ui.same_line() end
 local sChanged, sVal = ui.slider_float('##s_' .. id, cur, min_v, max_v)
 if sChanged and sVal ~= nil then cur = sVal; changed = true end
 if ui.same_line then ui.same_line() end
 if ui.button and ui.button(' + ##inc_' .. id) then
  cur = math.min(max_v, cur + step)
  changed = true
 end
 if ui.same_line then ui.same_line() end
 if ui.text then ui.text(string.format(' %s: %+.0f px', label, cur)) end
 if changed then
  tableRef[key] = cur
  R.saveCustomHUDConfig()
  if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
  elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
 end
end

local function renderSteppedScale(ui, label, tableRef, key, min_v, max_v, step, id)
 local cur = (tableRef and type(tableRef[key]) == 'number') and tableRef[key] or 1.0
 local changed = false
 if ui.button and ui.button(' - ##dec_' .. id) then
  cur = math.max(min_v, cur - step)
  changed = true
 end
 if ui.same_line then ui.same_line() end
 local sChanged, sVal = ui.slider_float('##s_' .. id, cur, min_v, max_v)
 if sChanged and sVal ~= nil then cur = sVal; changed = true end
 if ui.same_line then ui.same_line() end
 if ui.button and ui.button(' + ##inc_' .. id) then
  cur = math.min(max_v, cur + step)
  changed = true
 end
 if ui.same_line then ui.same_line() end
 if ui.text then ui.text(string.format(' %s: %.2fx', label, cur)) end
 if changed then
  tableRef[key] = cur
  R.saveCustomHUDConfig()
  if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
  elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
 end
end

local function renderSteppedOpacity(ui, label, tableRef, key, min_v, max_v, step, id)
 local cur = (tableRef and type(tableRef[key]) == 'number') and tableRef[key] or 0.95
 local changed = false
 if ui.button and ui.button(' - ##dec_' .. id) then
  cur = math.max(min_v, cur - step)
  changed = true
 end
 if ui.same_line then ui.same_line() end
 local sChanged, sVal = ui.slider_float('##s_' .. id, cur, min_v, max_v)
 if sChanged and sVal ~= nil then cur = sVal; changed = true end
 if ui.same_line then ui.same_line() end
 if ui.button and ui.button(' + ##inc_' .. id) then
  cur = math.min(max_v, cur + step)
  changed = true
 end
 if ui.same_line then ui.same_line() end
 if ui.text then ui.text(string.format(' %s: %.2f', label, cur)) end
 if changed then
  tableRef[key] = cur
  R.saveCustomHUDConfig()
  if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
  elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
 end
end

local function renderElementBlock(ui, title, elemKey, hasPos)
 local he = R.customHUDConfig and R.customHUDConfig.hudElements
 local elem = he and he[elemKey]
 if not elem then return end
 if ui.tree_node and ui.tree_node(title .. '##tree_' .. elemKey) then
  renderSteppedScale(ui, 'Scale', elem, 'scale', 0.1, 4.0, 0.05, elemKey .. '_sc')
  if hasPos ~= false then
   renderSteppedSlider(ui, title .. ' X', elem, 'x', -2500.0, 2500.0, 5.0, elemKey .. '_x')
   renderSteppedSlider(ui, title .. ' Y (Up+ / Dn-)', elem, 'y', -2500.0, 2500.0, 5.0, elemKey .. '_y')
  end
  renderSteppedOpacity(ui, 'Opacity', elem, 'opacity', 0.0, 1.0, 0.05, elemKey .. '_op')
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
  -- SECTION 2: AC8 HUD tune & Layout (Unified Old Script Compliant)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('AC8 HUD tune & Layout##section_hud_tune') then
   if ui.text then
    ui.text('Controls PitchLadder, Heading, Whisky, Radar, AircraftInfo, Score, Locator, DrawCanvas.')
    ui.text('Geometry offsets in pixels (-2500 ~ +2500 px), Scale (0.1 ~ 4.0x), Opacity (0.0 ~ 1.0).')
   end
   if ui.separator then ui.separator() end

   -- 1. PitchLadder & Children
   local he = R.customHUDConfig and R.customHUDConfig.hudElements
   if he and ui.tree_node and ui.tree_node('PitchLadder (人工水平儀)##tree_ladder') then
    local t_ladder = he.ladder
    if t_ladder then
     renderSteppedScale(ui, 'Scale', t_ladder, 'scale', 0.1, 4.0, 0.05, 'ladder_sc')
     renderSteppedSlider(ui, 'PitchLadder X', t_ladder, 'x', -2500.0, 2500.0, 5.0, 'ladder_x')
     renderSteppedSlider(ui, 'PitchLadder Y (Up+ / Dn-)', t_ladder, 'y', -2500.0, 2500.0, 5.0, 'ladder_y')
     renderSteppedOpacity(ui, 'Opacity', t_ladder, 'opacity', 0.0, 1.0, 0.05, 'ladder_op')

     -- SUB-NODE: PichHeading (PitchLadder Child)
     if ui.tree_node and ui.tree_node('PichHeading (進行方向 / PitchLadder Child)##tree_heading') then
      local t_heading = he.heading
      if t_heading then
       renderSteppedScale(ui, 'Heading Scale', t_heading, 'scale', 0.1, 4.0, 0.05, 'heading_sc')
       renderSteppedSlider(ui, 'Heading X', t_heading, 'x', -2500.0, 2500.0, 5.0, 'heading_x')
       renderSteppedSlider(ui, 'Heading Y (Up+ / Dn-)', t_heading, 'y', -2500.0, 2500.0, 5.0, 'heading_y')
       renderSteppedOpacity(ui, 'Heading Opacity', t_heading, 'opacity', 0.0, 1.0, 0.05, 'heading_op')
      end
      if ui.tree_pop then ui.tree_pop() end
     end

     -- SUB-NODE: WhiskyMarkPanel (PitchLadder Child)
     if ui.tree_node and ui.tree_node('WhiskyMarkPanel (正面Wマーク / PitchLadder Child)##tree_whisky') then
      local t_whisky = he.whisky
      if t_whisky then
       renderSteppedScale(ui, 'WhiskyMark Scale', t_whisky, 'scale', 0.1, 4.0, 0.05, 'whisky_sc')
       renderSteppedSlider(ui, 'WhiskyMark X', t_whisky, 'x', -2500.0, 2500.0, 5.0, 'whisky_x')
       renderSteppedSlider(ui, 'WhiskyMark Y (Up+ / Dn-)', t_whisky, 'y', -2500.0, 2500.0, 5.0, 'whisky_y')
       renderSteppedOpacity(ui, 'WhiskyMark Opacity', t_whisky, 'opacity', 0.0, 1.0, 0.05, 'whisky_op')
      end
      if ui.tree_pop then ui.tree_pop() end
     end
    end
    if ui.tree_pop then ui.tree_pop() end
   end

   -- 2. Radar (Parent container)
   renderElementBlock(ui, 'Radar (レーダー親コンテナ / 3縮尺・円枠一括)', 'radar', true)

   -- 3. AircraftInfo (Common draw container)
   renderElementBlock(ui, 'AircraftInfo (機体情報 / 残弾・武装・HP)', 'info', true)

   -- 4. Score / MissionInfo
   renderElementBlock(ui, 'Score / MissionInfo (スコア・作戦目標・タイマー)', 'score', true)

   -- 5. Locator (Screen-edge arrows)
   renderElementBlock(ui, 'Locator (画面外ターゲット矢印・ロケーター)', 'locator', true)

   -- 6. Draw canvas (Background)
   renderElementBlock(ui, 'Draw canvas (Background / メイン背景)', 'drawcanvas', false)

   if ui.separator then ui.separator() end

   -- ACTION BUTTONS (Save, Load Saved, Reset ALL to base)
   if ui.button and ui.same_line then
    if ui.button('Save##btn_save') then
     R.saveCustomHUDConfig()
     print('[AC8-VR] Configuration saved to disk.')
    end
    ui.same_line()
    if ui.button('Load Saved##btn_load') then
     R.reloadCustomHUDConfig()
     if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
     elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
     print('[AC8-VR] Configuration reloaded from disk.')
    end
    ui.same_line()
    if ui.button('Reset ALL to base##btn_reset_all') then
     local h = R.customHUDConfig and R.customHUDConfig.hudElements
     if h then
      h.ladder = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.heading = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.whisky = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.radar = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.info = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.score = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.locator = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.drawcanvas = { scale = 1.0, opacity = 0.95 }
      R.saveCustomHUDConfig()
      if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
      elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
      print('[AC8-VR] All HUD elements reset to base defaults.')
     end
    end
   end

   -- Emergency Recovery Button
   if ui.button and ui.button('>> Emergency: Force Show ALL HUD <<##btn_emergency_hud') then
    if R.triggerInstantAwake then R.triggerInstantAwake() end
   end
   if ui.text then
    ui.text('Emergency recovery: Toggles HUD off & on in 4 frames to wake up all dormant HUD elements')
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
