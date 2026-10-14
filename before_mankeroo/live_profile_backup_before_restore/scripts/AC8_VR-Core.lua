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
 local pc=invoke(real.api,'get_player_controller',0)
 if not R.isLiveObject(pc)then pc=nil end
 local hud=invoke(pc,'GetHUD');if not R.isLiveObject(hud)then hud=nil end
 local root=invoke(hud,'get_property','HudWidget');if not R.isLiveObject(root)then root=nil end
 local hn=invoke(hud,'get_full_name') or '';local rn=invoke(root,'get_full_name') or ''
 local identity=hn..'|'..rn
 if identity~=R.context.identity then R.context.epoch=R.context.epoch+1;R.context.changedAt=R.tick;R.context.identity=identity end
 R.context.pc=pc;R.context.hud=hud;R.context.root=root;R.context.hudName=hn;R.context.rootName=rn;R.context.flight=hn:match('^LiveMainHUDParent4K_C ')~=nil
end
function R.connect(key)
 if R.connected[key]then return end;R.connected[key]=true
 real.sdk.callbacks[key](function(...)
  if key=='on_pre_engine_tick'then R.contextTick()
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
local journals={['ac8_cinematic_ui_restore.json']=true,['ac8_hangar_restore_v48.json']=true,['ac8_ladder.json']=true,['ac8_hud_layout_cache.json']=true}
R.json={load_file=R.read,dump_file=function(name,value,indent)
 if journals[name]then R.cache[name]=nil;return realJSON.dump_file(name,value,indent)end
end}
function R.log(_)end -- Legacy adapters receive a quiet logger; errors stay in R.errors.
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
