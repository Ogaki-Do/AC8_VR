-- Shared lifetime checks, current HUD context and deterministic callback dispatch.
-- Configuration reads are cached; only recovery/configuration journals may be written.
-- All section factories must register before any module starts changing game state.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
-- Shared pause/tutorial support, owned by Core.
local function ensureTutorialState(R)
 if R.tutorialState then return R.tutorialState end
 local T={version=1,visible=false,widgets={},roots={},contents={}}
 R.tutorialState=T
 local function call(o,k,...)
  if not o or(o~=uevr.api and not R.isLiveObject(o))then return end
  local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
 end
 local function full(o)return call(o,'get_full_name')end
 local function prop(o,k)return call(o,'get_property',k)end
 local tutorialClasses={}
 local rootPaths={
  'WidgetBlueprintGeneratedClass /Game/NUI/Common/WBP_Menu_Common_Dialog_000.WBP_Menu_Common_Dialog_000_C',
  'Class /Script/Live.LiveNUICommonDialogWidget',
 }
 local function dialogRoots()
  for _,path in ipairs(rootPaths)do
   local cls=tutorialClasses[path];local identity=full(cls)
   if identity~=path then cls=call(uevr.api,'find_uobject',path);tutorialClasses[path]=cls;identity=full(cls)end
   if identity==path then
    local objects=call(cls,'get_objects_matching',false)
    if type(objects)=='table'then return objects end
   end
  end
  return {}
 end
 local function dialogContents(root,rootName)
  local tree=prop(root,'WidgetTree');local first=prop(tree,'RootWidget')
  local path=rootName:match('^%S+ (.+)$');local out={}
  if not first or not path then return out end
  local queue,seen={first},{};local index=1
  while index<=#queue and index<=4096 do
   local w=queue[index];index=index+1
   if w and not seen[w]then
    seen[w]=true;local n=full(w)or'';local p=n:match('^%S+ (.+)$')
    if p and p:sub(1,#path+1)==path..'.'then
     if n:match('^WBP_Menu_Common_Dialog_Parts_Contents_CP_002_C ')then out[#out+1]=w end
     local count=call(w,'GetChildrenCount')
     if type(count)=='number'and count>=0 and count%1==0 then
      for i=0,math.min(count,512)-1 do
       local child=call(w,'GetChildAt',i)
       if child and #queue<4096 then queue[#queue+1]=child end
      end
     end
     local nested=prop(prop(w,'WidgetTree'),'RootWidget')
     if nested and #queue<4096 then queue[#queue+1]=nested end
    end
   end
  end
  return out
 end
 local function discoverTutorials()
  local rows={}
  for i,root in ipairs(dialogRoots())do
   if i>4096 then break end
   local n=full(root)or''
   if n:match('^WBP_Menu_Common_Dialog_000_C /Engine/Transient%.')and not n:find('Default__',1,true)then
    rows[#rows+1]=root
    for _,w in ipairs(dialogContents(root,n))do rows[#rows+1]=w end
   end
  end
  return rows
 end
 local function active(w)
  if not call(w,'GetParent')then return false end
  for _=1,12 do
   local v=call(w,'GetVisibility')
   if v==1 or v==2 or call(w,'GetRenderOpacity')==0 then return false end
   local parent=call(w,'GetParent');if not parent then return true end
   local selected=call(parent,'GetActiveWidget')
   if selected and full(selected)~=full(w)then return false end
   w=parent
  end
  return false
 end
 function T.get(pc,hn,paused,tick)
  tick=R.tick or tick or 0
  if paused~=true or not(hn or''):match('^LiveMainHUDParent%w*_C ')then
   if T.paused or T.visible then T.visible=false;T.roots={};T.contents={};T.paused=false;T.stamp=nil end
   return T
  end
  if T.stamp==tick and T.hud==hn then return T end
  local edge=not T.paused or T.hud~=hn
  T.stamp=tick;T.hud=hn;T.paused=true
  if edge or not T.candidates or (#T.candidates==0 and tick%15==0) then
   T.candidates={}
   for _,w in ipairs(discoverTutorials())do
    local n=full(w)or''
    if n:find('/Engine/Transient.',1,true)and(n:match('^WBP_Menu_Common_Dialog_000_C ')or n:match('^WBP_Menu_Common_Dialog_Parts_Contents_CP_002_C '))then
     T.candidates[#T.candidates+1]={name=n,object=w}
    end
   end
  end
  local widgets,roots,contents={},{},{}
  for _,c in ipairs(T.candidates or{})do
   local w=c.object
   if full(w)~=c.name then w=call(uevr.api,'find_uobject',c.name);if full(w)~=c.name then w=nil end;c.object=w end
   if w then
    widgets[#widgets+1]=w;local n=c.name
    if not n:find('Default__',1,true)then
     if n:match('^WBP_Menu_Common_Dialog_000_C ')and call(w,'GetVisibility')==0 then roots[#roots+1]={object=w,name=n,path=n:match('^%S+ (.+)$')}end
     if n:match('^WBP_Menu_Common_Dialog_Parts_Contents_CP_002_C ')and active(w)then contents[#contents+1]={object=w,name=n}end
    end
   end
  end
  T.widgets=widgets;T.roots=roots;T.contents=contents;T.visible=false
  for _,root in ipairs(roots)do
   for _,c in ipairs(contents)do if c.name:find(root.path..'.',1,true)then T.visible=true;break end end
   if T.visible then break end
  end
  return T
 end
 return T
end

local function newHUDDefaultsStore(files)
 local D={file='AC8_VR-HUDDefaults.json',backup='AC8_VR-HUDDefaults.backup.json'}
 local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
 local function equal(a,b)
  if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
  for k,x in pairs(a)do if not equal(x,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end;return true
 end
 local function param(p)
  return type(p)=='table'and type(p.enabled)=='boolean'and type(p.x)=='number'and p.x==p.x and math.abs(p.x)<=4000 and
   type(p.y)=='number'and p.y==p.y and math.abs(p.y)<=4000 and type(p.scale)=='number'and p.scale>=.1 and p.scale<=3
 end
 local function layout(v)
  if type(v)~='table'or type(v.groups)~='table'or(v.components~=nil and type(v.components)~='table')then return end
  for _,k in ipairs({'ladder','radar','info'})do if not param(v.groups[k])then return end end
  local n=0;for k,p in pairs(v.components or{})do n=n+1;if n>24 or type(k)~='string'or not param(p)then return end end
  if v.canvas then local c=v.canvas
   if not param(c)or type(c.extraWidth)~='number'or c.extraWidth~=c.extraWidth or c.extraWidth<0 or c.extraWidth>4000 or
    type(c.extraHeight)~='number'or c.extraHeight~=c.extraHeight or c.extraHeight<0 or c.extraHeight>4000 or type(c.inheritClip)~='boolean'then return end
  end
  local out=copy(v);out.components=out.components or{};out.simpleGroups=out.simpleGroups or{};out.simpleGroups.navigation=nil
  for k,p in pairs(out.simpleGroups)do
   if type(k)~='string'or type(p)~='table'or type(p.x)~='number'or p.x~=p.x or math.abs(p.x)>4000 or type(p.y)~='number'or p.y~=p.y or math.abs(p.y)>4000 then return end
  end
  return out
 end
 local function decode(v)
  if type(v)~='table'or v.version~=1 then return end
  local a,b=layout(v.default),layout(v.shared);if a and b then return{version=1,default=a,shared=b}end
 end
 function D:init()
  if self.db then return true end
  local ok,v=pcall(files.load_file,self.file);local valid=ok and decode(v)
  if not valid then local good,b=pcall(files.load_file,self.backup);valid=good and decode(b)end
  if valid then self.db=valid;return true end
  local good,old=pcall(files.load_file,'AC8_VR-HUDLayouts.json')
  if good and type(old)=='table'then
   local a,b=layout(old.default),layout(old.allPlanes or old.default)
   if a and b then self.db={version=1,default=a,shared=b};return true end
  end
  local p={groups={},components={},simpleGroups={}}
  for _,k in ipairs({'ladder','radar','info'})do p.groups[k]={enabled=false,x=0,y=0,scale=1}end
  self.db={version=1,default=copy(p),shared=copy(p)}
  if not ok or v~=nil then self.invalid=true;self.message='Invalid shared HUD defaults; existing files preserved.'end
  return true
 end
 function D:saveShared(value,global)
  self:init();local next=layout(value)
  if self.invalid or not next then return false,self.message or'Invalid shared HUD layout.'end
  local db={version=1,default=global and copy(next)or copy(self.db.default),shared=next}
  local good,result=pcall(files.dump_file,self.backup,self.db,2);local readOK,b=pcall(files.load_file,self.backup)
  if not good or result==false or not readOK or not equal(decode(b),self.db)then return false,'Shared HUD backup failed verification.'end
  good,result=pcall(files.dump_file,self.file,db,2);readOK,b=pcall(files.load_file,self.file)
  if not good or result==false or not readOK or not equal(decode(b),db)then pcall(files.dump_file,self.file,self.db,2);return false,'Shared HUD save failed; previous layout retained.'end
  self.db=db;return true,global and'Global HUD default saved; aircraft presets unchanged.'or'Saved shared HUD layout.'
 end
 function D:saveGlobal(value)return self:saveShared(value,true)end
 function D:view()
  local P={message='AC8_VR-AircraftPresets.lua is absent; general HUD controls remain available.'}
  function P:init()D:init();self.db={version=1,perPlaneEnabled=false,useDefaultForAllPlanes=true,default=copy(D.db.default),allPlanes=copy(D.db.shared),planes={}};return true end
  function P:selected()return copy(D.db.shared),'all planes'end
  function P:saveAll(v)local ok,msg=D:saveShared(v);if ok then self:init();self.force=true end;return ok,msg end
  function P:saveGlobalHUD(v)local ok,msg=D:saveGlobal(v);if ok then self:init();self.force=true end;return ok,msg end
  function P:count()return 0 end
  function P:savePlane()return false,self.message end
  P.setPerPlaneEnabled=P.savePlane;P.setShared=P.savePlane;P.saveUISizePreferences=P.savePlane
  P.copy=copy;P.layout=layout;P.plane=function()return false end
  P:init();return P
 end
 D.copy=copy;D.layout=layout;return D
end

assert(not registry.sections['core'], 'Duplicate AC8 VR section: core')
registry.sections['core'] = function(R)
-- AC8 utility services and inherited Flat2VR adaptations.
local real=uevr;local realJSON=json
local R={version=105,modVersion='0.1.0.58',tick=0,domains={},connected={},context={epoch=0},cache={},errors={},inheritedSetup={},layoutEnabled=false}
_G.AC8Runtime=R
_G.__AC8_VR_RUNTIME__=R
R.ensureTutorialState=function()return ensureTutorialState(R)end
R.newHUDDefaultsStore=newHUDDefaultsStore
local order={'presentation','admission','layout','camera','utility','loading','intro','development'}
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
function R.objectCall(o,k,...)
 if not R.isLiveObject(o)then return nil end
 return invoke(o,k,...)
end
-- Shared discovery within one engine tick.
local widgetWalk={}
function R.ownedWidgets(root,fresh)
 if widgetWalk.tick~=R.tick or widgetWalk.epoch~=R.context.epoch then
  widgetWalk={tick=R.tick,epoch=R.context.epoch,roots={}}
 end
 local name=R.objectCall(root,'get_full_name')
 if not name then return nil end
 local cached=widgetWalk.roots[name]
 if not fresh and cached and cached.root==root then
  local alive=true
  for _,w in ipairs(cached.rows)do if not R.isLiveObject(w)then alive=false;break end end
  if alive then return cached.rows,cached.names end
 end
 local tree=R.objectCall(root,'get_property','WidgetTree')
 local first=R.objectCall(tree,'get_property','RootWidget')
 if not R.isLiveObject(first)then return nil end
 local rows,queue,seen,names={},{root},{},{}
 local index=1
 while index<=#queue do
  if index>8192 then return nil end
  local w=queue[index];index=index+1
  local n=R.objectCall(w,'get_full_name')
  if not n then return nil end
  if not seen[n]then
   seen[n]=true;rows[#rows+1]=w;names[w]=n
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
 widgetWalk.roots[name]={root=root,rows=rows,names=names}
 return rows,names
end
-- Facts are refreshed lazily once per callback phase, only if a selected feature asks.
local current={epoch=0};local contextStamp=-1;local factStamp=-1;local facts={};local phase=0
local function refresh()
 if contextStamp==phase then return end;contextStamp=phase
 local pc=invoke(real.api,'get_player_controller',0);if not R.isLiveObject(pc)then pc=nil end
 local hud=R.objectCall(pc,'GetHUD');if not R.isLiveObject(hud)then hud=nil end
 local root=R.objectCall(hud,'get_property','HudWidget');if not R.isLiveObject(root)then root=nil end
 local hn=R.objectCall(hud,'get_full_name')or'';local rn=R.objectCall(root,'get_full_name')or''
 local identity=hn..'|'..rn
 if identity~=current.identity then current.epoch=current.epoch+1;current.changedAt=R.tick;current.identity=identity end
 current.pc=pc;current.hud=hud;current.root=root;current.hudName=hn;current.rootName=rn
 current.flight=hn:match('^LiveMainHUDParent%w*_C ')~=nil
end
R.context=setmetatable({},{
 __index=function(_,key)refresh();return current[key]end,
 __newindex=function(_,key,val)current[key]=val end
})
local function fact(key,reader)
 if factStamp~=phase then factStamp=phase;facts={}end
 if not facts[key]then facts[key]={reader()}end
 return table.unpack(facts[key])
end
function R.viewTargetName()
 return fact('viewTargetName',function()return R.objectCall(R.objectCall(R.context.pc,'GetViewTarget'),'get_full_name')or''end)
end
local statics
function R.gameStatics()
 if not R.isLiveObject(statics)then statics=invoke(real.api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics')end
 return statics
end
function R.paused()return fact('paused',function()return R.objectCall(R.gameStatics(),'IsGamePaused',R.context.pc)end)end
function R.matchState()
 return fact('matchState',function()
  local state=R.objectCall(R.gameStatics(),'GetGameState',R.context.pc)
  local name=R.objectCall(state,'get_full_name')or''
  local level=(R.objectCall(R.context.pc,'get_full_name')or''):match('%s(.+%.PersistentLevel)%.')
  if not level or not name:match('^LiveGameState ')or not name:find(' '..level..'.',1,true)then return nil end
  local v=R.objectCall(state,'get_property','MatchState')
  if type(v)=='string'then return v end
  if v~=nil then local ok,text=pcall(function()return v:to_string()end);if ok and type(text)=='string'then return text end end
 end)
end
R.settingOwners={}
function R.setOwnership(owner,channel,active)
 local rows=R.settingOwners[channel]or{};R.settingOwners[channel]=rows;rows[owner]=active==true or nil
end
function R.settingsBusy(channel,owner)
 for key in pairs(R.settingOwners[channel]or{})do if key~=owner then return true end end;return false
end
function R.recoverSettings(file,allowed)
 local ok,journal=pcall(realJSON.load_file,file)
 if not ok or type(journal)~='table'or type(journal.values)~='table'or next(journal.values)==nil then return true end
 local values,before={},{}
 for key,value in pairs(journal.values)do
  if not allowed[key]or(type(value)~='string'and type(value)~='number')then R.errors[file]='Invalid recovery settings';return false end
  values[key]=tostring(value)
 end
 local function get(key)local good,v=pcall(function()return real.params.vr:get_mod_value(key)end);if good and v~=nil then return tostring(v)end end
 local function same(a,b)return a==b or(tonumber(a)and tonumber(b)and tonumber(a)==tonumber(b))end
 for key in pairs(values)do before[key]=get(key);if before[key]==nil then R.errors[file]='Settings unavailable for removed-feature recovery';return false end end
 for key,value in pairs(values)do
  local good=pcall(function()real.params.vr.set_mod_value(key,value)end)
  if not good or not same(get(key),value)then
   for restore,v in pairs(before)do pcall(function()real.params.vr.set_mod_value(restore,v)end)end
   R.errors[file]='Removed-feature recovery write failed; previous values restored';return false
  end
 end
 local saved=pcall(function()real.params.vr.save_config()end)
 if not saved then R.errors[file]='Recovered in memory; save unavailable, journal retained';return false end
 local cleared=pcall(realJSON.dump_file,file,{version=1,values={}},2)
 if not cleared then R.errors[file]='Recovered settings; journal could not be cleared';return false end
 return true
end
function R.contextTick(advance)
 if advance~=false then R.tick=R.tick+1 end
 phase=phase+1
 if advance~=false then
  if R.profileCount then R.profileCount('contextTick') end
  if (R.tick % 30 == 0) and R.applyActiveCameraOffset then
   local curPlane = R.getCurrentPlaneName and R.getCurrentPlaneName()
   if curPlane ~= current.planeName then
    current.planeName = curPlane
    pcall(R.applyActiveCameraOffset)
   end
  end
  if R.updateInstantAwakeCycle then
   R.updateInstantAwakeCycle()
  end
  if R.pendingLocatorSyncTick and R.tick >= R.pendingLocatorSyncTick then
   R.pendingLocatorSyncTick = nil
   pcall(R.syncLocatorConfigToDLL)
  end
  if R.pendingSaveTick and R.tick >= R.pendingSaveTick then
   R.pendingSaveTick = nil
   pcall(R.saveCustomHUDConfig)
  end
 end
end
function R.connect(key)
 if R.connected[key]then return end;R.connected[key]=true
 real.sdk.callbacks[key](function(...)
  if key=='on_pre_engine_tick'then
   if registry.state=='waiting'then registry.start(true)end
   R.contextTick()
   if R.tickProfiler then R.tickProfiler() end
  elseif key=='on_post_engine_tick'or key=='on_pre_viewport_client_draw'then R.contextTick(false)end
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
local journals={
 ['ac8_cinematic_ui_restore.json']=true,
 ['ac8_hangar_restore_v48.json']=true,
 ['ac8_ladder.json']=true,
 ['ac8_hud_layout_cache.json']=true,
 ['CustomHUDPosition.json']=true,
 ['ac8_target_arrow_shift_controls.json']=true,
 ['ac8_offscreen_group_controls.json']=true,
 ['ac8_debug_telemetry.json']=true,
 ['AC8_VR-CockpitScaleRestore.json']=true,
 ['AC8_VR-CinematicUIRestore.json']=true,
 ['AC8_VR-HangarRestoreV48.json']=true,
 ['AC8_VR-Ladder.json']=true,
 ['AC8_VR-HUDLayoutCache.json']=true,
 ['AC8_VR-WingmanSelectorBaseline.json']=true,
 ['AC8_VR-WingmanStatusBaseline.json']=true,
 ['AC8_VR-TargetArrowShiftControls.json']=true,
 ['AC8_VR-OffscreenGroupControls.json']=true,
 ['AC8_VR-TargetSettings.json']=true,
 ['AC8_VR-WorldTargetControls.json']=true,
 ['AC8_VR-BombLandingControls.json']=true,
 ['AC8_VR-ArrowLiveControls.json']=true
}
R.realJSON = realJSON
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
 if not cfg.vrRuntimeMode then cfg.vrRuntimeMode = 'Auto' end
 if not cfg.cinematicPresentation then cfg.cinematicPresentation = { enabled = false } end
 if not cfg.hudPresentation then
  cfg.hudPresentation = {
   enabled = false,
   distance = 1.0,
   size = 1.0,
   curvature = 113.625,
   curvedOverlay = true
  }
 end
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
 if not he.nose then he.nose = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.wingman then he.wingman = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 } end
 if not he.drawcanvas then he.drawcanvas = { scale = 1.0, opacity = 0.95 } end

 if not cfg.worldTargets or type(cfg.worldTargets) ~= 'table' then
  cfg.worldTargets = {
   boxScale = 0.25,
   labelScale = 0.25,
   fontScale = 1.0,
   lineSpacing = 15.0,
   labelRaise = 0.0,
   blueSaturation = 1.1
  }
 end
 if not cfg.specialWeapons or type(cfg.specialWeapons) ~= 'table' then
  cfg.specialWeapons = {
   bombFOV = 9.0
  }
 end

 if not cfg.cameraOffsets then
  cfg.cameraOffsets = { default = { forward = 0.0, right = 0.0, up = 0.0 }, planes = {} }
 end
 if not cfg.cameraOffsets.default then
  cfg.cameraOffsets.default = { forward = 0.0, right = 0.0, up = 0.0 }
 end
 if not cfg.cameraOffsets.planes then cfg.cameraOffsets.planes = {} end
 return cfg
end

local function loadCustomHUDConfig()
 local ok, data = pcall(function() return realJSON.load_file('CustomHUDPosition.json') end)
 if ok and type(data) == 'table' then
  print('[AC8-VR] Loaded HUD config from CustomHUDPosition.json')
  return ensureCustomHUDDefaults(data), 'CustomHUDPosition.json'
 end
 print('[AC8-VR] Initialized default HUD config (target: CustomHUDPosition.json)')
 return ensureCustomHUDDefaults({}), 'CustomHUDPosition.json'
end

-- Common Core Runtime Adapter Scaffold (OpenXR vs OpenVR isolation)
R.RuntimeAdapter = {
 mode = 'Auto',
 resolvedMode = 'OpenXR',
 resolve = function(self)
  local cfgMode = (R.customHUDConfig and R.customHUDConfig.vrRuntimeMode) or 'Auto'
  self.mode = cfgMode
  if cfgMode == 'OpenXR' or cfgMode == 'OpenVR' then
   self.resolvedMode = cfgMode
   return self.resolvedMode
  end
  local isOvr = false
  local isOxr = false
  pcall(function()
   local vr = real.params and real.params.vr
   if vr then
    if vr.is_openvr and vr:is_openvr() then isOvr = true end
    if vr.is_openxr and vr:is_openxr() then isOxr = true end
   end
  end)
  if isOvr and not isOxr then
   self.resolvedMode = 'OpenVR'
  else
   self.resolvedMode = 'OpenXR'
  end
  return self.resolvedMode
 end,
 isOpenXR = function(self)
  return (self.resolvedMode or self:resolve()) == 'OpenXR'
 end,
 isOpenVR = function(self)
  return (self.resolvedMode or self:resolve()) == 'OpenVR'
 end
}

local function getCachedDisplaySize()
 local s = R.cachedViewportSize
 if not s then
  pcall(function()
   local engine = uevr and uevr.api and uevr.api:get_engine()
   local gvc = engine and engine:get_property('GameViewport')
   local vs = gvc and gvc:get_property('ViewportSize')
   if vs and vs.X > 0 and vs.Y > 0 then
    s = { X = vs.X, Y = vs.Y }
    R.cachedViewportSize = s
   end
  end)
 end
 local w = (s and type(s.X) == 'number' and s.X > 0) and s.X or 3840.0
 local h = (s and type(s.Y) == 'number' and s.Y > 0) and s.Y or 2160.0
 return w, h
end
R.getCachedDisplaySize = getCachedDisplaySize

function R.syncLocatorConfigToDLL()
 local he = R.customHUDConfig and R.customHUDConfig.hudElements
 local loc = he and he.locator
 local nose = he and he.nose
 local ladder = he and he.ladder
 local lx = (ladder and tonumber(ladder.x)) or 0.0
 local ly = (ladder and tonumber(ladder.y)) or 0.0
 local lsc = (ladder and tonumber(ladder.scale)) or 1.0

 local locX = (loc and tonumber(loc.x)) or 0.0
 local locY = (loc and tonumber(loc.y)) or 0.0
 local locSc = (loc and tonumber(loc.scale)) or 1.0

 local noseX = (nose and tonumber(nose.x)) or 0.0
 local noseY = (nose and tonumber(nose.y)) or 0.0
 local noseSc = (nose and tonumber(nose.scale)) or 1.0

 local userLocX = lx + locX
 local userLocY = ly + locY
 local userNoseX = lx + noseX
 local userNoseY = ly + noseY

 -- Dynamic resolution & margin-aware locator baseline (Unified cross-display formula)
 local dw, dh = getCachedDisplaySize()
 local canvasSize = R.cachedCanvasVirtualSize
  or (R.getCanvasVirtualSize and select(1, R.getCanvasVirtualSize()))
  or { X = dw, Y = dh }
 local safeH = canvasSize and math.min(canvasSize.Y, canvasSize.X * (9.0 / 16.0)) or dh
 local safeW = canvasSize and math.min(canvasSize.X, canvasSize.Y * (16.0 / 9.0)) or dw
 local marginX = canvasSize and math.max(0.0, (canvasSize.X - safeW) * 0.5) or 0.0
 local marginY = canvasSize and math.max(0.0, (canvasSize.Y - safeH) * 0.5) or 0.0

 -- Base calibrated values (Unified formula):
 -- Target final screen center: (CX, CY) = (1920.0 + marginX, 1080.0 + marginY)
 -- Base ox = -1232.0 (cancels native X bias to land on screen center 1920.0)
 -- Base oy = -2026.0 (cancels native cockpit Y bias ~3106.0 to land on screen center 1080.0, identical to FPM)
 -- Base groupOffsetX = -1414.0 (-180px canvas bias + -1234px center offset)
 local baseLocX = -1232.0
 local baseLocY = -2026.0
 local baseGroupX = -1414.0

 local ox = baseLocX + marginX + userLocX
 local oy = baseLocY + marginY - userLocY
 local sc = 1.3 * locSc * lsc

 local arrowCfg = { enabled = true, offsetX = ox, offsetY = oy, scale = sc }
 -- LowestPriorityDynamicDrawCanvas has native 180px right-bias; baseGroupX + marginX centers it.
 local groupCfg = { enabled = true, offsetX = baseGroupX + marginX + userLocX, scale = 0.96 }
 R.targetArrowShiftCache = arrowCfg
 R.offscreenGroupCache = groupCfg

 local j = R.realJSON or realJSON or rawget(_G, 'json')
 if j and j.dump_file then
  pcall(function() j.dump_file('AC8_VR-TargetArrowShiftControls.json', arrowCfg, 2) end)
  pcall(function() j.dump_file('AC8_VR-OffscreenGroupControls.json', groupCfg, 2) end)
  pcall(function() j.dump_file('ac8_target_arrow_shift_controls.json', arrowCfg, 2) end)
  pcall(function() j.dump_file('ac8_offscreen_group_controls.json', groupCfg, 2) end)
 end
 print(string.format('[AC8-VR] Synced Locator to DLL: ox=%.1f, oy=%.1f, sc=%.2f, nose=(%.1f, %.1f)', ox, oy, sc, userNoseX, userNoseY))
end

R.customHUDConfig, R.customHUDConfigPath = loadCustomHUDConfig()
R.RuntimeAdapter:resolve()
pcall(R.syncLocatorConfigToDLL)
pcall(R.syncWorldTargetsToFiles)

function R.isCinematicEnabled()
 local cfg=R.customHUDConfig and R.customHUDConfig.cinematicPresentation
 return cfg and cfg.enabled==true
end

function R.syncWorldTargetsToFiles()
 local cfg = R.customHUDConfig
 if not cfg then return end
 local j = R.realJSON or realJSON or rawget(_G, 'json')
 if cfg.worldTargets then
  local wt = cfg.worldTargets
  local targetCtrl = {
   boxScale = wt.boxScale or 0.25,
   enabled = true,
   fontScale = wt.fontScale or 1.0,
   labelScale = wt.labelScale or 0.25,
   lineSpacing = wt.lineSpacing or 15.0
  }
  local worldCtrl = {
   enabled = true,
   useFlatLabelOffsets = true,
   labelRaise = wt.labelRaise or 0.0,
   leftLabelDrop = 3,
   blueSaturation = wt.blueSaturation or 1.1
  }
  R.targetSettingsCache = targetCtrl
  R.worldTargetControlsCache = worldCtrl
  if j and j.dump_file then
   pcall(function() j.dump_file('AC8_VR-TargetSettings.json', targetCtrl, 2) end)
   pcall(function() j.dump_file('AC8_VR-WorldTargetControls.json', worldCtrl, 2) end)
   pcall(function() j.dump_file('ac8_workshop_target_controls.json', targetCtrl, 2) end)
   pcall(function() j.dump_file('ac8_world_target_controls.json', worldCtrl, 2) end)
  end
 end
 if cfg.specialWeapons and cfg.specialWeapons.bombFOV then
  local bombCtrl = {
   enabled = true,
   fovAdjustmentDegrees = cfg.specialWeapons.bombFOV or 9.0,
   version = 76
  }
  R.bombLandingControlsCache = bombCtrl
  if j and j.dump_file then
   pcall(function() j.dump_file('AC8_VR-BombLandingControls.json', bombCtrl, 2) end)
   pcall(function() j.dump_file('ac8_bomb_landing_controls.json', bombCtrl, 2) end)
  end
 end
end

function R.saveCustomHUDConfig()
 if not R.customHUDConfig then return end
 pcall(function() realJSON.dump_file('CustomHUDPosition.json', R.customHUDConfig, 2) end)
 pcall(R.syncLocatorConfigToDLL)
 pcall(R.syncWorldTargetsToFiles)
 print('[AC8-VR] Configuration saved to CustomHUDPosition.json')
end

function R.reloadCustomHUDConfig()
 R.customHUDConfig, R.customHUDConfigPath = loadCustomHUDConfig()
 pcall(R.syncLocatorConfigToDLL)
 pcall(R.syncWorldTargetsToFiles)
 if R.invalidateHUDLayoutPlan then pcall(R.invalidateHUDLayoutPlan) end
 if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated) end
 if R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
 if R.applyActiveCameraOffset then pcall(R.applyActiveCameraOffset) end
 print('[AC8-VR] Configuration reloaded and applied to DLL from ' .. tostring(R.customHUDConfigPath))
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
local hudActionMsg = ''
local camActionMsg = ''
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
  R.pendingLocatorSyncTick = R.tick + 2
  R.pendingSaveTick = R.tick + 30
  if R.invalidateHUDLayoutPlan then pcall(R.invalidateHUDLayoutPlan) end
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
  R.pendingLocatorSyncTick = R.tick + 2
  R.pendingSaveTick = R.tick + 30
  if R.invalidateHUDLayoutPlan then pcall(R.invalidateHUDLayoutPlan) end
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
  R.pendingSaveTick = R.tick + 30
  if R.invalidateHUDLayoutPlan then pcall(R.invalidateHUDLayoutPlan) end
  if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
  elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
 end
end

local function renderElementBlock(ui, title, elemKey, hasPos, hasOpacity)
 local he = R.customHUDConfig and R.customHUDConfig.hudElements
 local elem = he and he[elemKey]
 if not elem then return end
 if ui.tree_node and ui.tree_node(title .. '##tree_' .. elemKey) then
  renderSteppedScale(ui, 'Scale', elem, 'scale', 0.1, 4.0, 0.05, elemKey .. '_sc')
  if hasPos ~= false then
   renderSteppedSlider(ui, title .. ' X', elem, 'x', -2500.0, 2500.0, 5.0, elemKey .. '_x')
   renderSteppedSlider(ui, title .. ' Y (Up+ / Dn-)', elem, 'y', -2500.0, 2500.0, 5.0, elemKey .. '_y')
  end
  if hasOpacity ~= false then
   renderSteppedOpacity(ui, 'Opacity', elem, 'opacity', 0.0, 1.0, 0.05, elemKey .. '_op')
  end
  if ui.tree_pop then ui.tree_pop() end
 end
end

-- UEVR Script UI (ImGui)
pcall(function()
 real.sdk.callbacks.on_draw_ui(function()
  local ui=rawget(_G,'imgui')
  if not ui then return end

  if ui.text_colored then
   ui.text_colored('=== AC8 VR Tuning Suite (' .. tostring(R.modVersion or 'v0.1.0.44-WIP') .. ') ===', 0.2, 0.8, 1.0, 1.0)
   if ui.separator then ui.separator() end
  end

  -- =========================================================================
  -- SECTION 1: AC8 VR Master Settings
  -- =========================================================================
  if ui.tree_node and ui.tree_node('AC8 VR Master Settings') then
   local curMode = (R.customHUDConfig and R.customHUDConfig.vrRuntimeMode) or 'Auto'
   local resolvedMode = (R.RuntimeAdapter and R.RuntimeAdapter:resolve()) or 'OpenXR'
   if ui.text then
    ui.text(string.format('VR Runtime Mode: %s (Active Adapter: %s)', curMode, resolvedMode))
   end
   if ui.button and ui.same_line then
    if ui.button('Auto##btn_rt_auto') then
     if not R.customHUDConfig then R.customHUDConfig = ensureCustomHUDDefaults({}) end
     R.customHUDConfig.vrRuntimeMode = 'Auto'
     R.RuntimeAdapter:resolve()
     R.saveCustomHUDConfig()
    end
    ui.same_line()
    if ui.button('Force OpenXR##btn_rt_oxr') then
     if not R.customHUDConfig then R.customHUDConfig = ensureCustomHUDDefaults({}) end
     R.customHUDConfig.vrRuntimeMode = 'OpenXR'
     R.RuntimeAdapter:resolve()
     R.saveCustomHUDConfig()
    end
    ui.same_line()
    if ui.button('Force OpenVR##btn_rt_ovr') then
     if not R.customHUDConfig then R.customHUDConfig = ensureCustomHUDDefaults({}) end
     R.customHUDConfig.vrRuntimeMode = 'OpenVR'
     R.RuntimeAdapter:resolve()
     R.saveCustomHUDConfig()
    end
   end
   if ui.separator then ui.separator() end

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
   local pres = R.customHUDConfig and R.customHUDConfig.hudPresentation
   if pres and ui.tree_node and ui.tree_node('UEVR UI Settings (Distance, Size, OverlayType)##tree_pres') then
    local curPresEnabled = (pres.enabled == true)
    if ui.checkbox then
     local changed, newVal = ui.checkbox('Override UEVR UI Presentation on startup##chk_pres_ovr', curPresEnabled)
     if changed and newVal ~= nil then
      pres.enabled = newVal
      R.saveCustomHUDConfig()
      if newVal and R.applyPresentationDefaults then
       R.applyPresentationDefaults(true)
      end
      print(string.format('[AC8-VR] UEVR UI Presentation override set to: %s', tostring(newVal)))
     end
    end
    if ui.text_colored then
     if curPresEnabled then
      ui.text_colored('Status: OVERRIDING (Script sets UI Distance, Size, Curvature on start)', 0.2, 1.0, 0.2, 1.0)
     else
      ui.text_colored('Status: OFF (Using user settings from UEVR config.txt - No Lua overwrite)', 0.4, 0.8, 1.0, 1.0)
     end
    end
    if curPresEnabled then
     local scChanged, scVal = renderSteppedScale(ui, 'UI Size (Scale)', pres, 'size', 0.1, 5.0, 0.05, 'pres_size')
     local distChanged, distVal = renderSteppedSlider(ui, 'UI Distance (m)', pres, 'distance', 0.1, 10.0, 0.05, 'pres_dist')
     local curveChanged, curveVal = renderSteppedSlider(ui, 'UI Curvature (deg)', pres, 'curvature', 1.0, 180.0, 1.0, 'pres_curve')
     if ui.checkbox then
      local ovChanged, ovVal = ui.checkbox('Enable Curved Overlay (UI_OverlayType=1)##chk_pres_curve', pres.curvedOverlay ~= false)
      if ovChanged and ovVal ~= nil then
       pres.curvedOverlay = ovVal
       R.saveCustomHUDConfig()
       if R.applyPresentationDefaults then R.applyPresentationDefaults(true) end
      end
     end
     if (scChanged or distChanged or curveChanged) and R.applyPresentationDefaults then
      R.saveCustomHUDConfig()
      R.applyPresentationDefaults(true)
     end
     if ui.button and ui.button('Apply Now to UEVR##btn_pres_apply') then
      if R.applyPresentationDefaults then R.applyPresentationDefaults(true) end
     end
    end
    if ui.tree_pop then ui.tree_pop() end
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
   if he and ui.tree_node and ui.tree_node('PitchLadder (Artificial Horizon / Speed / Alt)##tree_ladder') then
    local t_ladder = he.ladder
    if t_ladder then
     renderSteppedScale(ui, 'Scale', t_ladder, 'scale', 0.1, 4.0, 0.05, 'ladder_sc')
     renderSteppedSlider(ui, 'PitchLadder X', t_ladder, 'x', -2500.0, 2500.0, 5.0, 'ladder_x')
     renderSteppedSlider(ui, 'PitchLadder Y (Up+ / Dn-)', t_ladder, 'y', -2500.0, 2500.0, 5.0, 'ladder_y')
     renderSteppedOpacity(ui, 'Opacity', t_ladder, 'opacity', 0.0, 1.0, 0.05, 'ladder_op')

     -- SUB-NODE: WhiskyMarkPanel (PitchLadder Child)
     if ui.tree_node and ui.tree_node('WhiskyMarkPanel (Center W Mark / PitchLadder Child)##tree_whisky') then
      local t_whisky = he.whisky
      if t_whisky then
       renderSteppedScale(ui, 'WhiskyMark Scale', t_whisky, 'scale', 0.1, 4.0, 0.05, 'whisky_sc')
       renderSteppedSlider(ui, 'WhiskyMark X', t_whisky, 'x', -2500.0, 2500.0, 5.0, 'whisky_x')
       renderSteppedSlider(ui, 'WhiskyMark Y (Up+ / Dn-)', t_whisky, 'y', -2500.0, 2500.0, 5.0, 'whisky_y')
       renderSteppedOpacity(ui, 'WhiskyMark Opacity', t_whisky, 'opacity', 0.0, 1.0, 0.05, 'whisky_op')
      end
      if ui.tree_pop then ui.tree_pop() end
     end

     -- SUB-NODE: PichHeading (Flight Path Marker / PitchLadder Child)
     if ui.tree_node and ui.tree_node('PitchHeading (Velocity Vector / PitchLadder Child)##tree_heading') then
      local t_heading = he.heading
      if t_heading then
       renderSteppedScale(ui, 'Heading Scale', t_heading, 'scale', 0.1, 4.0, 0.05, 'heading_sc')
       renderSteppedSlider(ui, 'Heading X', t_heading, 'x', -2500.0, 2500.0, 5.0, 'heading_x')
       renderSteppedSlider(ui, 'Heading Y (Up+ / Dn-)', t_heading, 'y', -2500.0, 2500.0, 5.0, 'heading_y')
       renderSteppedOpacity(ui, 'Heading Opacity', t_heading, 'opacity', 0.0, 1.0, 0.05, 'heading_op')
      end
      if ui.tree_pop then ui.tree_pop() end
     end

     -- SUB-NODE: Locator (Target Direction Arrow / PitchLadder Child)
     if ui.tree_node and ui.tree_node('Locator (Target Arrow / PitchLadder Child)##tree_locator') then
      local t_locator = he.locator
      if t_locator then
       renderSteppedScale(ui, 'Locator Scale', t_locator, 'scale', 0.1, 4.0, 0.05, 'locator_sc')
       renderSteppedSlider(ui, 'Locator X', t_locator, 'x', -2500.0, 2500.0, 5.0, 'locator_x')
       renderSteppedSlider(ui, 'Locator Y (Up+ / Dn-)', t_locator, 'y', -2500.0, 2500.0, 5.0, 'locator_y')
      end
      if ui.tree_pop then ui.tree_pop() end
     end

     -- SUB-NODE: Nose Guide (Aircraft Forward Direction Arrow when looking sideways)
     if ui.tree_node and ui.tree_node('Nose Guide (機首方向ガイド / Camera Sideways)##tree_nose') then
      local t_nose = he.nose
      if t_nose then
       renderSteppedScale(ui, 'Nose Guide Scale', t_nose, 'scale', 0.1, 4.0, 0.05, 'nose_sc')
       renderSteppedSlider(ui, 'Nose Guide X', t_nose, 'x', -2500.0, 2500.0, 5.0, 'nose_x')
       renderSteppedSlider(ui, 'Nose Guide Y (Up+ / Dn-)', t_nose, 'y', -2500.0, 2500.0, 5.0, 'nose_y')
      end
      if ui.tree_pop then ui.tree_pop() end
     end
    end
    if ui.tree_pop then ui.tree_pop() end
   end

   -- 2. Radar (Parent container)
   renderElementBlock(ui, 'Radar (MiniMap & Corners Group)', 'radar', true)

   -- 3. AircraftInfo (Common draw container)
   renderElementBlock(ui, 'AircraftInfo (Player Status, HP & Weapons)', 'info', true)

   -- 4. Score / MissionInfo
   renderElementBlock(ui, 'Score / MissionInfo (Score, Objective & Timer)', 'score', true)

   -- 6. Wingman (Formation Command)
   renderElementBlock(ui, 'Wingman (Formation Command Panel)', 'wingman', true)

   -- 7. Draw canvas (Background)
   renderElementBlock(ui, 'Draw Canvas (Main HUD Background)', 'drawcanvas', false)

   if ui.separator then ui.separator() end

   -- ACTION BUTTONS (Save, Load Saved, Reset ALL to base)
   if ui.button and ui.same_line then
    if ui.button('Save##btn_save') then
     R.saveCustomHUDConfig()
     hudActionMsg = '[OK] Configuration saved to disk.'
     print('[AC8-VR] Configuration saved to disk.')
    end
    ui.same_line()
    if ui.button('Load Saved##btn_load') then
     R.reloadCustomHUDConfig()
     hudActionMsg = '[OK] Loaded saved configuration from disk.'
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
      h.nose = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.wingman = { x = 0.0, y = 0.0, scale = 1.0, opacity = 0.95 }
      h.drawcanvas = { scale = 1.0, opacity = 0.95 }
      R.pendingSaveTick = nil
      pcall(R.syncLocatorConfigToDLL)
      if R.invalidateHUDLayoutPlan then pcall(R.invalidateHUDLayoutPlan) end
      if R.applyHUDLayoutIntegrated then pcall(R.applyHUDLayoutIntegrated)
      elseif R.applyAllHUDCustomPositions then pcall(R.applyAllHUDCustomPositions) end
      hudActionMsg = '[RESET] Reset to base defaults (Unsaved. Press Save to persist).'
      print('[AC8-VR] All HUD elements reset to base defaults in memory. (Not saved to disk until Save is pressed)')
     end
    end
   end
   if hudActionMsg and hudActionMsg ~= '' and ui.text then
    ui.text(hudActionMsg)
   end

   -- Emergency Recovery Button
   if ui.button and ui.button('>> Emergency: Force Show ALL HUD <<##btn_emergency_hud') then
    if R.triggerInstantAwake then R.triggerInstantAwake() end
   end
   if ui.text then
    ui.text('Emergency recovery: Toggles HUD off & on in 4 frames to wake up all dormant HUD elements')
   end

   -- Telemetry Dump Button
   if ui.button and ui.button('>> Dump Debug Telemetry Now <<##btn_dump_telemetry') then
    if R.DebugTelemetry and R.DebugTelemetry.dumpNow then
     R.DebugTelemetry.dumpNow('ui_button')
     hudActionMsg = '[OK] Telemetry dumped to ac8_debug_telemetry.json & jsonl!'
     print('[AC8-VR] ' .. hudActionMsg)
    end
   end

   if ui.tree_pop then ui.tree_pop() end
  end

  -- =========================================================================
  -- SECTION 3: 3D World Targets & Special Weapons (P2)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('3D World Targets & Special Weapons (P2)') then
   local wt = R.customHUDConfig and R.customHUDConfig.worldTargets
   local sw = R.customHUDConfig and R.customHUDConfig.specialWeapons
   if wt then
    if ui.text then ui.text('--- 3D Target Boxes & Labels ---') end
    -- Target Box Scale
    local bChanged, bVal = ui.slider_float('Target Box Scale', wt.boxScale or 0.25, 0.1, 2.0)
    if bChanged and bVal ~= nil then wt.boxScale = bVal; R.pendingSaveTick = R.tick + 60 end
    if ui.button and ui.same_line then
     if ui.button('-0.05##tb') then wt.boxScale = math.max(0.1, (wt.boxScale or 0.25) - 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('+0.05##tb') then wt.boxScale = math.min(2.0, (wt.boxScale or 0.25) + 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('Default (0.25)##tb_def') then wt.boxScale = 0.25; R.pendingSaveTick = R.tick + 60 end
    end

    -- Target Label Scale
    local lChanged, lVal = ui.slider_float('Target Label Scale', wt.labelScale or 0.25, 0.1, 2.0)
    if lChanged and lVal ~= nil then wt.labelScale = lVal; R.pendingSaveTick = R.tick + 60 end
    if ui.button and ui.same_line then
     if ui.button('-0.05##tl') then wt.labelScale = math.max(0.1, (wt.labelScale or 0.25) - 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('+0.05##tl') then wt.labelScale = math.min(2.0, (wt.labelScale or 0.25) + 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('Default (0.25)##tl_def') then wt.labelScale = 0.25; R.pendingSaveTick = R.tick + 60 end
    end

    -- Target Font Scale
    local fChanged, fVal = ui.slider_float('Target Font Scale', wt.fontScale or 1.0, 0.1, 2.0)
    if fChanged and fVal ~= nil then wt.fontScale = fVal; R.pendingSaveTick = R.tick + 60 end
    if ui.button and ui.same_line then
     if ui.button('-0.05##tf') then wt.fontScale = math.max(0.1, (wt.fontScale or 1.0) - 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('+0.05##tf') then wt.fontScale = math.min(2.0, (wt.fontScale or 1.0) + 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('Default (1.0)##tf_def') then wt.fontScale = 1.0; R.pendingSaveTick = R.tick + 60 end
    end

    -- Label Height Offset (labelRaise)
    local rChanged, rVal = ui.slider_float('Label Height Offset (px)', wt.labelRaise or 0.0, -200.0, 200.0)
    if rChanged and rVal ~= nil then wt.labelRaise = rVal; R.pendingSaveTick = R.tick + 60 end
    if ui.button and ui.same_line then
     if ui.button('-5px##lr') then wt.labelRaise = (wt.labelRaise or 0) - 5; R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('+5px##lr') then wt.labelRaise = (wt.labelRaise or 0) + 5; R.pendingSaveTick = R.tick + 60 end
    end

    -- Ally Blue Saturation
    local satChanged, satVal = ui.slider_float('Ally Blue Saturation', wt.blueSaturation or 1.1, 1.0, 1.5)
    if satChanged and satVal ~= nil then wt.blueSaturation = satVal; R.pendingSaveTick = R.tick + 60 end
    if ui.button and ui.same_line then
     if ui.button('-0.05##sat') then wt.blueSaturation = math.max(1.0, (wt.blueSaturation or 1.1) - 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('+0.05##sat') then wt.blueSaturation = math.min(1.5, (wt.blueSaturation or 1.1) + 0.05); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('Default (1.1)##sat_def') then wt.blueSaturation = 1.1; R.pendingSaveTick = R.tick + 60 end
    end
   end

   if sw then
    if ui.separator then ui.separator() end
    if ui.text then ui.text('--- Special Weapons (Bomb CCIP Sight) ---') end
    -- Bomb CCIP Ground FOV
    local fovChanged, fovVal = ui.slider_float('Bomb CCIP Ground FOV (deg)', sw.bombFOV or 9.0, 0.0, 20.0)
    if fovChanged and fovVal ~= nil then sw.bombFOV = fovVal; R.pendingSaveTick = R.tick + 60 end
    if ui.button and ui.same_line then
     if ui.button('-0.5 deg##bf') then sw.bombFOV = math.max(0.0, (sw.bombFOV or 9.0) - 0.5); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('+0.5 deg##bf') then sw.bombFOV = math.min(20.0, (sw.bombFOV or 9.0) + 0.5); R.pendingSaveTick = R.tick + 60 end
     ui.same_line()
     if ui.button('Default (9.0 deg)##bf_def') then sw.bombFOV = 9.0; R.pendingSaveTick = R.tick + 60 end
    end
   end

   if ui.separator then ui.separator() end
   if ui.button and ui.same_line then
    if ui.button('Save Target & Weapon Settings##btn_tw_save') then
     R.pendingSaveTick = nil
     R.saveCustomHUDConfig()
     hudActionMsg = '[OK] Target & Weapon settings saved to disk.'
     print('[AC8-VR] Target & Weapon settings saved to disk.')
    end
    ui.same_line()
    if ui.button('Reset Target & Weapon Defaults##btn_tw_reset') then
     if wt then
      wt.boxScale = 0.25
      wt.labelScale = 0.25
      wt.fontScale = 1.0
      wt.lineSpacing = 15.0
      wt.labelRaise = 0.0
      wt.blueSaturation = 1.1
     end
     if sw then sw.bombFOV = 9.0 end
     pcall(R.syncWorldTargetsToFiles)
     hudActionMsg = '[RESET] Target & Weapon settings reset to defaults (Unsaved).'
     print('[AC8-VR] Target & Weapon settings reset to defaults.')
    end
   end
   if ui.tree_pop then ui.tree_pop() end
  end

  -- =========================================================================
  -- SECTION 4: Cockpit Head / Camera Position (P1 & P3)
  -- =========================================================================
  if ui.tree_node and ui.tree_node('Cockpit Head Position / Camera Offset (P1 & P3)') then
   local plane = R.getCurrentPlaneName()
   local co = R.customHUDConfig.cameraOffsets
   local isPlaneSpecific = (plane and co.planes and co.planes[plane] ~= nil)

   if ui.text then
    ui.text('Current Aircraft: ' .. (plane or 'Unknown / Outside Cockpit'))
    if plane then
     if isPlaneSpecific then
      ui.text('Status: [Custom Offset ACTIVE for ' .. plane .. ']')
     else
      ui.text('Status: [Default (0, 0, 0 cm) in use]')
     end
    end
   end

   if plane and ui.button and ui.same_line then
    if ui.button('Save for Current Plane (' .. plane .. ')##btn_plane_save') then
     if not co.planes then co.planes = {} end
     local activeTarget = (isPlaneSpecific and co.planes[plane]) or co.default
     co.planes[plane] = {
      forward = activeTarget.forward or 0.0,
      right = activeTarget.right or 0.0,
      up = activeTarget.up or 0.0
     }
     R.saveCustomHUDConfig()
     R.applyActiveCameraOffset()
     camActionMsg = string.format('[OK] Saved custom offset for plane %s: (%.1f, %.1f, %.1f cm)', plane, co.planes[plane].forward, co.planes[plane].right, co.planes[plane].up)
     print('[AC8-VR] ' .. camActionMsg)
    end
    ui.same_line()
    if isPlaneSpecific then
     if ui.button('Clear Plane Offset (Use Default)##btn_plane_clear') then
      co.planes[plane] = nil
      R.saveCustomHUDConfig()
      R.applyActiveCameraOffset()
      camActionMsg = string.format('[CLEARED] Custom offset removed for %s. Using default.', plane)
      print('[AC8-VR] ' .. camActionMsg)
     end
    end
   end

   local activeTarget = (plane and isPlaneSpecific and co.planes[plane]) or co.default
   local fChanged, fVal = ui.slider_float('Forward Offset (cm)', activeTarget.forward or 0.0, -100.0, 100.0)
   if fChanged and fVal ~= nil then activeTarget.forward = fVal; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
   if ui.button and ui.same_line then
    if ui.button('-1.0cm##f') then activeTarget.forward = (activeTarget.forward or 0) - 1.0; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('-0.2cm##f') then activeTarget.forward = (activeTarget.forward or 0) - 0.2; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+0.2cm##f') then activeTarget.forward = (activeTarget.forward or 0) + 0.2; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+1.0cm##f') then activeTarget.forward = (activeTarget.forward or 0) + 1.0; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
   end

   local rChanged, rVal = ui.slider_float('Right Offset (cm)', activeTarget.right or 0.0, -50.0, 50.0)
   if rChanged and rVal ~= nil then activeTarget.right = rVal; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
   if ui.button and ui.same_line then
    if ui.button('-1.0cm##r') then activeTarget.right = (activeTarget.right or 0) - 1.0; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('-0.2cm##r') then activeTarget.right = (activeTarget.right or 0) - 0.2; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+0.2cm##r') then activeTarget.right = (activeTarget.right or 0) + 0.2; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+1.0cm##r') then activeTarget.right = (activeTarget.right or 0) + 1.0; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
   end

   local uChanged, uVal = ui.slider_float('Up Offset (cm)', activeTarget.up or 0.0, -50.0, 50.0)
   if uChanged and uVal ~= nil then activeTarget.up = uVal; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
   if ui.button and ui.same_line then
    if ui.button('-1.0cm##u') then activeTarget.up = (activeTarget.up or 0) - 1.0; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('-0.2cm##u') then activeTarget.up = (activeTarget.up or 0) - 0.2; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+0.2cm##u') then activeTarget.up = (activeTarget.up or 0) + 0.2; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
    ui.same_line()
    if ui.button('+1.0cm##u') then activeTarget.up = (activeTarget.up or 0) + 1.0; R.pendingSaveTick = R.tick + 60; R.applyActiveCameraOffset() end
   end

   if ui.separator then ui.separator() end

   -- ACTION BUTTONS (Save, Load Saved, Reset Camera to Defaults)
   if ui.button and ui.same_line then
    if ui.button('Save Default Offsets##btn_cam_save') then
     R.pendingSaveTick = nil
     R.saveCustomHUDConfig()
     camActionMsg = '[OK] Camera offsets saved to disk.'
     print('[AC8-VR] Camera offsets saved to disk.')
    end
    ui.same_line()
    if ui.button('Load Saved##btn_cam_load') then
     R.pendingSaveTick = nil
     R.reloadCustomHUDConfig()
     camActionMsg = '[OK] Loaded saved camera offsets from disk.'
     print('[AC8-VR] Camera offsets reloaded from disk.')
    end
    ui.same_line()
    if ui.button('Reset to Defaults (0, 0, 0 cm)##btn_cam_reset') then
     activeTarget.forward = 0.0
     activeTarget.right = 0.0
     activeTarget.up = 0.0
     R.pendingSaveTick = nil
     R.applyActiveCameraOffset()
     camActionMsg = '[RESET] Camera reset to (0, 0, 0 cm) (Unsaved. Press Save to persist).'
     print('[AC8-VR] Camera offsets reset to defaults in memory.')
    end
   end
   if camActionMsg and camActionMsg ~= '' and ui.text then
    ui.text(camActionMsg)
   end
   if ui.tree_pop then ui.tree_pop() end
  end
 end)
end)

R.connect('on_pre_engine_tick')


end

-- Registering files in any order produces the explicit initialization order.
-- A failed initializer is never retried in-place: restart the script environment.
local required={'core','cutscene_guard','inherited_hud','mission_loading','glow_lifecycle','target_presentation','target_labels','target_animation','target_pins','target_materials','hud_policy','glow_brightness','tutorial_fill','pause_attachment','hit_destroyed_restore','transitions','aircraft_presets','plane_camera','cinematic','cinematic_ownership','hud_layout','loading_icon','gameplay_camera','startup_movies'}
registry.required=required;registry.started={};registry.status={};registry.dependencies={}
local function initialize(key)
 local ok,err=pcall(registry.sections[key],rawget(_G,'AC8Runtime'))
 if not ok then
  registry.state='failed';registry.error=key..': '..tostring(err)
  print('AC8 VR startup failed: '..registry.error)
  error(registry.error)
 end
 registry.started[key]=true;registry.status[key]='started';registry.completed[#registry.completed+1]=key
end
function registry.start(finalize)
 if registry.state=='failed'or registry.state=='starting'or registry.state=='ready'then return end
 if not registry.started.core then initialize('core')end
 if not finalize then return end
 registry.state='starting'
 if not registry.sections.cinematic then
  local keys={UI_OverlayType=true,UI_Distance=true,UI_Size=true,UI_FollowView=true,UI_Y_Offset=true,UI_X_Offset=true,UI_Cylinder_Angle=true,VR_CameraForwardOffset=true,VR_CameraRightOffset=true,VR_CameraUpOffset=true}
  AC8Runtime.recoverSettings('AC8_VR-CinematicUIRestore.json',keys)
  AC8Runtime.recoverSettings('AC8_VR-HangarRestoreV48.json',keys)
 end
 AC8Runtime.recoverSettings('AC8_VR-CockpitScaleRestore.json',{VR_WorldScale=true})
 AC8Runtime.recoverSettings('AC8_VR-FlightUISizeRestore.json',{UI_Size=true})
 AC8Runtime.recoverSettings('AC8_VR-AircraftCameraRestore.json',{VR_CameraForwardOffset=true,VR_CameraRightOffset=true,VR_CameraUpOffset=true})
 if registry.sections.hud_layout or registry.sections.aircraft_presets then
  AC8Runtime.hudDefaults=newHUDDefaultsStore(json);AC8Runtime.hudDefaults:init()
 end
 for _,key in ipairs(required)do
  if not registry.started[key]then
   if registry.sections[key]then initialize(key)else registry.status[key]='file not selected'end
  end
 end
 registry.state='ready'
end

registry.start()
