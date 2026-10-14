-- Select the current player aircraft through its owned first-person camera.
-- Apply absolute UEVR offsets on selection/configuration/ownership changes only.
-- The data file is editable during play; manual UEVR edits persist between changes.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['plane_camera'], 'Duplicate AC8 VR section: plane_camera')
registry.sections['plane_camera'] = function(R)
do
-- Absolute UEVR settings, applied on aircraft/configuration/ownership changes.
-- No stereo pose callbacks and no save_config calls.
local R=AC8Runtime
local S={version=89,config={enabled=false,default={forward=-18,right=0,up=5},planes={}},nextRead=0,revision=0,status={state='waiting'},writes=0}
R.planeSpecificOffset=S
local host=R.host('utility','plane specific UEVR camera')
local keys={forward='VR_CameraForwardOffset',right='VR_CameraRightOffset',up='VR_CameraUpOffset'}
local axes={'forward','right','up'}
local function call(o,k,...)
 if not o or not R.isLiveObject(o)then return end
 local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function row(v)
 if type(v)~='table'then return end
 local result={}
 for _,axis in ipairs(axes)do local n=v[axis];if type(n)~='number'or n~=n or math.abs(n)>100 then return end;result[axis]=n end
 return result
end
-- Evaluate only the data table in an empty environment, validate all rows,
-- then replace the last known-good configuration as one unit.
local function readConfig()
 if R.tick<S.nextRead then return end;S.nextRead=R.tick+60
 local ok,text=pcall(function()return fs.read('AC8_VR-PerPlaneCameraOffsets.lua')end)
 if not ok or type(text)~='string'or text==''then
  if S.config.enabled then S.revision=S.revision+1 end
  S.config.enabled=false;S.lastText=nil;S.configError='AC8_VR-PerPlaneCameraOffsets.lua unavailable';return
 end
 if text==S.lastText then return end;S.lastText=text
 local chunk,err=load(text,'@AC8_VR-PerPlaneCameraOffsets.lua','t',{})
 if not chunk then S.configError=tostring(err);return end
 local good,c=pcall(chunk)
 if not good or type(c)~='table'or c.mode~='uevr_absolute'or type(c.enabled)~='boolean'or type(c.planes)~='table'or not row(c.default)then S.configError='Expected mode=uevr_absolute, enabled, default and planes';return end
 local validated={enabled=c.enabled,default=row(c.default),planes={}};local count=0
 for name,v in pairs(c.planes)do
  count=count+1;local value=row(v)
  if count>256 or type(name)~='string'or not name:match('^BP_PlayerPlane_[%w_]+_C$')or not value then S.configError='Invalid aircraft entry or offset outside -100..100';return end
  validated.planes[name]=value
 end
 S.config=validated;S.configError=nil;S.revision=S.revision+1
end
local function observed()
 local result={}
 for _,axis in ipairs(axes)do
  local ok,v=pcall(function()return uevr.params.vr:get_mod_value(keys[axis])end)
  local n=ok and tonumber(v);if not n or n~=n or math.abs(n)>1e9 then return end
  result[axis]=n
 end
 return result
end
-- Read-before-write transaction. A partial settings failure restores all
-- axes so the camera cannot be left at a mixture of two aircraft presets.
local function apply(value)
 local before=observed();if not before then return false,'UEVR camera settings unavailable' end
 for _,axis in ipairs(axes)do
  if before[axis]~=value[axis]then
   local ok=pcall(function()uevr.params.vr.set_mod_value(keys[axis],tostring(value[axis]))end)
   S.writes=S.writes+1
   local actual=observed()
   if not ok or not actual or actual[axis]~=value[axis]then
    for _,restoreAxis in ipairs(axes)do pcall(function()uevr.params.vr.set_mod_value(keys[restoreAxis],tostring(before[restoreAxis]))end)end
    return false,'UEVR write/readback failed; previous values restored where possible'
   end
  end
 end
 return true
end
local function presentationOwns(ci)
 return not ci or ci.maskActive or ci.hangarActive or ci.cameraLocked or ci.shotOverridesActive or ci.guardForced or ci.recoveringUI or
  (ci.saved and next(ci.saved)~=nil)or(ci.hangarSaved and next(ci.hangarSaved)~=nil)or ci.detectedMode=='cinematic'or ci.detectedMode=='hangar'
end
-- The aircraft Blueprints expose FirstPersonCamera. CameraComponent is used by
-- other view targets and is not a universal aircraft property. Always resolve
-- from the current view target; never choose a plane from a global actor list.
local function firstPersonCamera(target)
 local targetName=call(target,'get_full_name')
 local function verified(component)
  local name=call(component,'get_full_name')or''
  if not name:match('^LiveFirstPersonCameraComponent ')then return end
  local owner=call(component,'GetOwner')
  if not owner or call(owner,'get_full_name')~=targetName then return end
  return component,name
 end
 local active=call(target,'get_property','CameraComponent')
 if active then
  local component,name=verified(active)
  -- An explicit different camera must not be mistaken for the cockpit merely
  -- because the aircraft also owns an inactive first-person component.
  return component,name,component and 'CameraComponent' or 'different or unverified CameraComponent'
 end
 local component,name=verified(call(target,'get_property','FirstPersonCamera'))
 if component then return component,name,'FirstPersonCamera' end
 -- Older cooked variants can expose the component without a reflected member.
 -- GetComponentByClass searches only this actor's first-person camera class.
 if not R.isLiveObject(S.firstPersonCameraClass)then
  local ok,cls=pcall(function()return uevr.api:find_uobject('Class /Script/Live.LiveFirstPersonCameraComponent')end)
  S.firstPersonCameraClass=ok and cls or nil
 end
 if R.isLiveObject(S.firstPersonCameraClass)then
  component,name=verified(call(target,'GetComponentByClass',S.firstPersonCameraClass))
  if component then return component,name,'GetComponentByClass' end
 end
 return nil,'','no verified first-person camera'
end
local function update()
 if S.lastTick==R.tick then return end;S.lastTick=R.tick
 readConfig()
 local status={mode='uevr_absolute',state='waiting',configError=S.configError,writes=S.writes};S.status=status
 local ci=rawget(_G,'AC8_CinematicIntent')
 if presentationOwns(ci)then S.selection=nil;status.state='cinematic/hangar owns camera';return end
 local target=call(R.context.pc,'GetViewTarget')
 if not target then target=call(call(R.context.pc,'get_property','PlayerCameraManager'),'GetViewTarget')end
 local name=call(target,'get_full_name')or''
 local class=name:match('^(BP_PlayerPlane_[%w_]+_C) ')
 local camera,cameraName,lookup
 if R.context.flight and class then camera,cameraName,lookup=firstPersonCamera(target)end
 status.aircraftClass=class;status.viewTarget=name;status.camera=cameraName;status.cameraLookup=lookup
 local cockpit=R.context.flight and class and camera and not(R.missionLoading and R.missionLoading.active)
 status.selectionReason=not R.context.flight and 'outside flight HUD' or not class and 'view target is not a player aircraft' or
  (R.missionLoading and R.missionLoading.active)and 'mission loading' or not camera and 'first-person camera unavailable' or
  not S.config.planes[class]and 'aircraft has no configured override' or 'configured current aircraft'
 local desired=S.config.default;local selection='default'
 if S.config.enabled and cockpit and S.config.planes[class]then desired=S.config.planes[class];selection=class end
 if not S.config.enabled and not S.owned then status.state='disabled';return end
 local key=selection..':'..S.revision..':'..(cockpit and name or '')
 if S.selection~=key then
  if R.tick<(S.retryAt or 0)then status.state='waiting to retry UEVR write';return end
  local ok,err=apply(desired)
  if not ok then S.retryAt=R.tick+60;status.state='write failed';status.error=err;return end
  S.retryAt=nil;S.selection=key;S.owned=S.config.enabled;status.appliedThisTick=true
 end
 status.state=S.config.enabled and(selection=='default'and'default UEVR position'or'aircraft UEVR position')or'disabled; default restored'
 status.forward=desired.forward;status.right=desired.right;status.up=desired.up
 -- Manual menu tuning remains until the selection key changes. No per-tick
 -- readback is needed after a successful application.

end
host.sdk.callbacks.on_post_engine_tick(update)
host.sdk.callbacks.on_script_reset(function()
 if S.owned and not presentationOwns(rawget(_G,'AC8_CinematicIntent'))then apply(S.config.default)end
end)
end

end

if registry.start then registry.start() end
