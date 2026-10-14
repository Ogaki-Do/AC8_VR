-- Own world-label metrics, persistent box sizes, assignment pins and material saturation.
-- Keep native introduction animation intact. Material changes target current-world
-- instances; the cyan predicate reads material parameters, never flattened HUD pixels.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['target_labels'], 'Duplicate AC8 VR section: target_labels')
registry.sections['target_labels'] = function(R)
do
-- native scopes retain accepted text placement only. Box dimensions return
-- to the post-tick size writer, leaving the introduction's initial size native.
(function(uevr,json)
local R=AC8Runtime;local S={version=80,packet=nil,ticks=0};R.worldTargetLayout=S
local function call(o,k,...)if not o then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function valid(v,lo,hi)return type(v)=='number'and v==v and v>=lo and v<=hi end
local function update()
 local c=R.context;local level=c.flight and call(c.hud,'get_outer');local address=R.isLiveObject(level)and call(level,'get_address')or 0
 if not address then address=0 end
 local t=json.load_file('ac8_workshop_target_controls.json')or{}
 local w=json.load_file('ac8_world_target_controls.json')or{}
 local box,label,font,spacing=t.boxScale,t.labelScale,t.fontScale or 1,t.lineSpacing or 0
 if not valid(box,.1,2)or not valid(label,.1,2)or not valid(font,.1,2)or not valid(spacing,-200,200)then box,label,font,spacing=1,1,1,0 end
 local raise=valid(w.labelRaise,-200,200)and w.labelRaise or 0
 local leftDrop=valid(w.leftLabelDrop,-200,200)and w.leftLabelDrop or 0
 local on=address~=0 and t.enabled==true and w.enabled~=false
 local packet=string.format('%d|%d|%.9g|%.9g|%.9g|%.9g|%d|%.9g|%.9g',address,on and 1 or 0,box,label,font,spacing,w.useFlatLabelOffsets~=false and 1 or 0,raise,leftDrop)
 if packet~=S.packet then call(uevr.api,'dispatch_custom_event','AC8_WorldTargetLayout',packet);S.packet=packet end
 S.controls={enabled=on,boxScale=box,labelScale=label,fontScale=font,lineSpacing=spacing,useFlatLabelOffsets=w.useFlatLabelOffsets~=false,labelRaise=raise,leftLabelDrop=leftDrop}
end
uevr.sdk.callbacks.on_pre_engine_tick(function()S.ticks=S.ticks+1;update()end)
pcall(function()uevr.sdk.callbacks.on_script_reset(function()call(uevr.api,'dispatch_custom_event','AC8_WorldTargetLayout','0|0|1|1|1|0|0|0')end)end)
end)(AC8Runtime.host('utility','native world target layout'),AC8Runtime.json)
end


end
assert(not registry.sections['target_animation'], 'Duplicate AC8 VR section: target_animation')
registry.sections['target_animation'] = function(R)
do
-- Preserve native construction-time box dimensions. The original post-tick
-- scalar writer preserves the native large first appearance and shrinking path.
-- Only box fields are restored here; accepted native label metrics stay separate.
(function(uevr,json)
local R=AC8Runtime;local S={version=80,ticks=0,epoch=-1,rows={},writes=0};R.worldBoxDimensionRollback=S
local fields={'ContainerBoxImageSize','SelectTargetAddContainerBoxSize'}
local function call(o,k,...)if not o or(o~=uevr.api and not R.isLiveObject(o))then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function restore()
 for _,row in pairs(S.rows)do
  if call(row.actor,'get_full_name')==row.name then
   for _,key in ipairs(fields)do if call(row.actor,'get_property',key)==row.last[key]then call(row.actor,'set_property',key,row.original[key])end end
  end
 end
 S.rows={}
end
uevr.sdk.callbacks.on_post_engine_tick(function()
 S.ticks=S.ticks+1;local ctx=R.context
 if S.epoch~=ctx.epoch then restore();S.epoch=ctx.epoch end
 if not ctx.flight then return end
 local control=json.load_file('ac8_workshop_target_controls.json')or{}
 local factor=control.enabled==true and tonumber(control.boxScale)or 1
 if not factor or factor~=factor or factor<.1 or factor>2 then return end
 if factor==1 and not next(S.rows)then return end
 local level=(ctx.hudName or''):match('^LiveMainHUDParent4K_C (.+%.PersistentLevel)%.');if not level then return end
 -- Reuse the existing target-pin discovery (every 15 viewport draws) instead
 -- of adding the old full object search to every engine tick. Cold fallback
 -- runs once per HUD epoch. Actual animation acceptance/CPU cost are unmeasured.
 local pins=rawget(_G,'AC8TargetPinsV56');local components=pins and pins.hud==ctx.hudName and pins.components
 if not components then
  if S.coldEpoch~=ctx.epoch then
   local cls=call(uevr.api,'find_uobject','Class /Script/Engine.MaterialBillboardComponent')
   S.cold=call(cls,'get_objects_matching',false)or{};S.coldEpoch=ctx.epoch
  end
  components=S.cold or{}
 end
 local seen={}
 for _,component in ipairs(components)do
  local name=call(component,'get_full_name')or''
  if name:find(level..'.ChronicleTargetContainerActorBP_C_',1,true)and name:match('%.ContainerBox$')then
   local actor=call(component,'GetOwner');local n=call(actor,'get_full_name')
   if n and not seen[n]then
    seen[n]=true;local row=S.rows[n]
    if not row then
     local original={};for _,key in ipairs(fields)do original[key]=call(actor,'get_property',key)end
     if type(original[fields[1]])=='number'and type(original[fields[2]])=='number'then row={actor=actor,name=n,original=original,last={}};S.rows[n]=row end
    end
    if row then for _,key in ipairs(fields)do
     local wanted=row.original[key]*factor
     if call(actor,'get_property',key)~=wanted then call(actor,'set_property',key,wanted);S.writes=S.writes+1 end
     row.last[key]=wanted
    end end
   end
  end
 end
 for n in pairs(S.rows)do if not seen[n]then S.rows[n]=nil end end
end)
uevr.sdk.callbacks.on_script_reset(restore)
end)(AC8Runtime.host('utility','world box animation'),AC8Runtime.json)
end


end
assert(not registry.sections['target_pins'], 'Duplicate AC8 VR section: target_pins')
registry.sections['target_pins'] = function(R)
do
-- target pins.
(function(uevr,json,print)

-- Assignment artwork: native SetElements owns world billboard size; Lua owns attachment offsets and the separate HUD-locator size.
local api=uevr.api
local previous=rawget(_G,'AC8TargetPinsV56');if previous and previous.restore then previous.restore()end
local S={version=59,ticks=0,rows={},writes=0,failures=0};rawset(_G,'AC8TargetPinsV56',S)
local function call(o,k,...)if not o then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function full(o)return call(o,'get_full_name')end
local function prop(o,k)return call(o,'get_property',k)end
local function xy(v)
 local ok,x,y=pcall(function()return v.X,v.Y end)
 if ok and type(x)=='number'and type(y)=='number'and x==x and y==y and math.abs(x)<10000 and math.abs(y)<10000 then return {X=x,Y=y}end
end
local mathLib=call(api,'find_uobject','KismetMathLibrary /Script/Engine.Default__KismetMathLibrary')
local function equal(a,b)return a and b and math.abs(a.X-b.X)<.0001 and math.abs(a.Y-b.Y)<.0001 end
local function put(o,key,v)
 local made=call(mathLib,'MakeVector2D',v.X,v.Y)
 if made then call(o,'set_property',key,made)end
 if not equal(xy(prop(o,key)),v)then pcall(function()local p=o:get_property(key);p.X=v.X;p.Y=v.Y end)end
 return equal(xy(prop(o,key)),v)
end
local function restore(row)
 if full(row.object)~=row.name then return end
 for key,v in pairs(row.original)do if equal(xy(prop(row.object,key)),row.last[key])then put(row.object,key,v)end end
end
S.restore=function()call(api,'dispatch_custom_event','AC8_WorldPipScale','1');S.stopped=true;for _,row in pairs(S.rows)do restore(row)end;S.rows={}end
local function apply(o,keys,kind,factor,seen)
 local name=full(o);if not name or seen[name]then return end;seen[name]=true
 local row=S.rows[name]
 if not row then
  local original={};for _,key in ipairs(keys)do original[key]=xy(prop(o,key));if not original[key]then S.failures=S.failures+1;return end end
  row={name=name,object=o,kind=kind,original=original,last={}};S.rows[name]=row
 end
 for _,key in ipairs(keys)do
  local current=xy(prop(o,key));local base=row.original[key];local last=row.last[key]
  if current and last then
   -- Keep the unmodified baseline independently on each axis when the game
   -- updates only one axis; never multiply our previous output again.
   if math.abs(current.X-last.X)>.0001 then base.X=current.X end
   if math.abs(current.Y-last.Y)>.0001 then base.Y=current.Y end
  end
  local wanted={X=base.X*factor,Y=base.Y*factor}
  if not equal(current,wanted)then
   if put(o,key,wanted)then S.writes=S.writes+1 else S.failures=S.failures+1 end
  end
  row.last[key]=wanted
 end
end
-- Send the requested scale before this engine tick constructs billboard proxies.
uevr.sdk.callbacks.on_pre_engine_tick(function()
 if S.stopped then return end
 local controls=json.load_file('ac8_workshop_target_controls.json')
 local factor=type(controls)=='table'and controls.enabled and tonumber(controls.boxScale)or 1
 if not factor or factor~=factor or factor<.1 or factor>2 then return end
 if S.nativeScale~=factor then call(api,'dispatch_custom_event','AC8_WorldPipScale',tostring(factor));S.nativeScale=factor end
end)
uevr.sdk.callbacks.on_pre_viewport_client_draw(function()
 if S.stopped then return end;S.ticks=S.ticks+1
 local controls=json.load_file('ac8_workshop_target_controls.json')
 local factor=type(controls)=='table'and controls.enabled and tonumber(controls.boxScale)or 1
 if not factor or factor<.1 or factor>2 then return end
 local hud=call(call(api,'get_player_controller',0),'GetHUD');local hn=full(hud)or''
 local level=hn:match('^LiveMainHUDParent4K_C (.+%.PersistentLevel)%.');local seen={}
 if level then
  if S.ticks%15==1 or S.hud~=hn then
   S.components=call(call(api,'find_uobject','Class /Script/Engine.MaterialBillboardComponent'),'get_objects_matching',false)or{}
  end
  S.hud=hn
  for _,c in ipairs(S.components or{})do
   local n=full(c)or''
   if n:find(level..'.ChronicleTargetContainerActorBP_C_',1,true)and(n:match('%.ClockTargetPinBillboardImage$')or n:match('%.AntiClockTargetPinBillboardImage$'))then
    apply(call(c,'GetOwner'),{'ClockTargetPinOffset','AntiClockTargetPinOffset'},'world-actor-offsets',factor,seen)
   end
  end
  local canvas=prop(hud,'DynamicCanvas')
  for i=0,math.min(call(canvas,'GetChildrenCount')or 0,64)-1 do
   local w=call(canvas,'GetChildAt',i);local n=full(w)or''
   if n:match('^WBP_HUD_DynamicWidget_Parts_Locator_000_C ')and n:match('%.WBP_LocatorWidget$')then apply(w,{'TargetPinSize'},'HUD-locator',factor,seen)end
  end
 end
 for name,row in pairs(S.rows)do if not seen[name]then restore(row);S.rows[name]=nil end end
 if S.ticks%30==1 then
  local rows={};for _,r in pairs(S.rows)do rows[#rows+1]={name=r.name,kind=r.kind,original=r.original,current=r.last}end
  
 end
end)
pcall(function()uevr.sdk.callbacks.on_script_reset(S.restore)end)

end)(AC8Runtime.host('utility','ac8_target_pins.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['target_materials'], 'Duplicate AC8 VR section: target_materials')
registry.sections['target_materials'] = function(R)
do
-- World-target material energy uses the native value. Saturation is adjusted
-- only on eligible target-owned instance materials; alpha is preserved.
local previous=rawget(_G,'AC8WorldToneV65')
if previous and previous.restore then previous.restore()end
rawset(_G,'AC8WorldToneV65',nil)
end

do
-- Color treatment is owned by actual current-world target instance materials,
-- never inferred from flattened HUD/movie pixels.
(function(uevr,json)
local R=AC8Runtime;local S={version=79,ticks=0,epoch=-1,components={},saved={},writes=0,failures=0};R.worldTargetSaturation=S
local function call(o,k,...)if not o then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function full(o)return R.isLiveObject(o)and call(o,'get_full_name')end
local function prop(o,k)return R.isLiveObject(o)and call(o,'get_property',k)end
local names=call(uevr.api,'find_uobject','KismetStringLibrary /Script/Engine.Default__KismetStringLibrary')
local mathLib=call(uevr.api,'find_uobject','KismetMathLibrary /Script/Engine.Default__KismetMathLibrary')
local parameter=call(names,'Conv_StringToName','Color')
local function color(v)local ok,r,g,b,a=pcall(function()return v.R,v.G,v.B,v.A end);if ok and type(r)=='number'and type(g)=='number'and type(b)=='number'and type(a)=='number'and r==r and g==g and b==b and a==a then return{R=r,G=g,B=b,A=a}end end
local function same(a,b)return a and b and math.abs(a.R-b.R)<.00001 and math.abs(a.G-b.G)<.00001 and math.abs(a.B-b.B)<.00001 and math.abs(a.A-b.A)<.00001 end
local function cyan(c)return c and c.A>0 and c.R>=0 and c.G>c.R*1.5 and c.B>c.R*1.5 end
local function get(m)return R.isLiveObject(m)and parameter and color(call(m,'K2_GetVectorParameterValue',parameter))end
local function set(m,c)local v=call(mathLib,'MakeColor',c.R,c.G,c.B,c.A);if not v then return false end;call(m,'SetVectorParameterValue',parameter,v);return same(get(m),c)end
-- Increase saturation around luminance, then normalize back to the original
-- peak intensity. This is a material-parameter edit, not a screen-pixel filter.
local function saturated(c,factor)
 local peak=math.max(c.R,c.G,c.B);local gray=c.R*.2126+c.G*.7152+c.B*.0722
 local r,g,b=math.max(0,gray+(c.R-gray)*factor),math.max(0,gray+(c.G-gray)*factor),math.max(0,gray+(c.B-gray)*factor)
 local newPeak=math.max(r,g,b);local gain=newPeak>0 and peak/newPeak or 1
 return{R=r*gain,G=g*gain,B=b*gain,A=c.A}
end
S.saturated=saturated
local function restore(n,row)if full(row.material)==n and same(get(row.material),row.last)then set(row.material,row.original)end end
local function reset()for n,row in pairs(S.saved)do restore(n,row)end;S.saved={}end
local function apply(m,kind,factor)
 local n=full(m)or'';if not n:match('^MaterialInstanceDynamic ')then return end
 local current=get(m);if not cyan(current)then S.saved[n]=nil;return end
 local row=S.saved[n]
 if not row then row={material=m,original=current,kind=kind};S.saved[n]=row
 elseif row.last and not same(current,row.last)then row.original=current end
 local wanted=saturated(row.original,factor)
 if not same(current,wanted)then if set(m,wanted)then S.writes=S.writes+1 else S.failures=S.failures+1;return end end
 row.last=wanted;row.seen=S.ticks
end
uevr.sdk.callbacks.on_post_engine_tick(function()
 S.ticks=S.ticks+1;local c=R.context;local level=(c.hudName or''):match('^LiveMainHUDParent4K_C (.+%.PersistentLevel)%.')
 local control=json.load_file('ac8_world_target_controls.json')or{};local factor=tonumber(control.blueSaturation)or 1.1
 if factor~=factor or factor<1 or factor>1.5 then factor=1 end
 S.factor=factor
 if S.epoch~=c.epoch then reset();S.epoch=c.epoch;S.components={};S.nextScan=0 end
 if not level or control.enabled==false or factor==1 then reset();return end
 if S.ticks>=(S.nextScan or 0)then
  S.nextScan=S.ticks+120
  S.components={};local cls=call(uevr.api,'find_uobject','Class /Script/Engine.MaterialBillboardComponent')
  for _,o in ipairs(call(cls,'get_objects_matching',false)or{})do local n=full(o)or''
   if n:find(level..'.ChronicleTargetContainerActorBP_C_',1,true)and n:match('%.ContainerBox$')then S.components[#S.components+1]={object=o,name=n}end
  end
 end
 for _,entry in ipairs(S.components)do local box=entry.object
  if full(box)==entry.name then local m=call(box,'GetMaterial',0);local mn=full(m)or''
   if mn:find('MID_M_HUD_TargetContainer3DUI_000_',1,true)and cyan(get(m))then
    local actor=call(box,'GetOwner');apply(m,'world outline',factor);apply(prop(actor,'EscortMaterialInst'),'escort glyph',factor)
    for _,key in ipairs({'AllianceText','ObjectTypeText','ObjectCallsignText','DistanceText','GamerTagText','NextTargetText'})do local text=prop(actor,key);apply(call(text,'GetMaterial',0),key,factor)end
   end
  end
 end
 for n,row in pairs(S.saved)do if row.seen~=S.ticks then restore(n,row);S.saved[n]=nil end end
end)
pcall(function()uevr.sdk.callbacks.on_script_reset(reset)end)
end)(AC8Runtime.host('utility','world ally escort saturation'),AC8Runtime.json)
end


end

if registry.start then registry.start() end
