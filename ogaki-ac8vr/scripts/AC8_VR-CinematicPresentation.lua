-- Own cinematic/hangar UI and camera transitions, including interrupted-session recovery.
-- Save settings before acquiring ownership and restore them before releasing it.
-- PlaneCamera and HUD defaults defer while this module owns those settings.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['cutscene_guard'], 'Duplicate AC8 VR section: cutscene_guard')
registry.sections['cutscene_guard'] = function(R)
-- OFF時は完全休眠（レンダースレッド登録ゼロ・Tickゼロ・探索ゼロ）
local cfg = R and R.customHUDConfig and R.customHUDConfig.cinematicPresentation
if not (cfg and cfg.enabled == true) then
    return
end
do
-- Flat2VR Modding Community and Discord: inherited cutscene_guard_v1. Track render heartbeats, rescue stalls reversibly, restore owned settings. Hangar is excluded from Screen Mode rescue.
(function(uevr,json,print)


local LOG = "[AC8-GUARD]"

local CFG = {
    STALL_SEC   = 2.5,   
    RESTORE_SEC = 3.0,   
    PREVENT_STALL = 0.5,
    PAWN_EVERY  = 20,    
    WARMUP      = 30,    
    MAX_RESCUE  = 8,     

    PREVENT     = true,  
    RESCUE      = true,  
    RESTORE     = true,  

    LEVEL2       = false,
    LEVEL2_AFTER = 5.0,  
}

local KEY        = "VR_2DScreenMode"
local METHOD_KEY = "VR_RenderingMethod"
local MONO_VALUE = "4"

local S = {
    beats = 0,     
    seen  = -1,    
    stall = 0.0,   
    ok_t  = 0.0,   
    T     = 0.0,   
    forced = false,
    prev  = nil,   
    hb_ok = nil,   
    since_force = 0.0, 
    l2 = false, prev_method = nil, 
    pawn  = nil,
    frames = 0,
    rescues = 0,
    last_rescue_t = -999,
    started = false,
}

local TRUE_S, FALSE_S = "true", "false"





local function mv_get(k)
    local vr = uevr and uevr.params and uevr.params.vr
    if not (vr and vr.get_mod_value) then return nil end
    local ok, v = pcall(function() return vr:get_mod_value(k) end)
    if ok and v ~= nil then return tostring(v) end
    return nil
end

local function mv_set(k, v)
    local vr = uevr and uevr.params and uevr.params.vr
    if not (vr and vr.set_mod_value) then return false end
    local ok = pcall(function() vr.set_mod_value(k, tostring(v)) end)
    return ok
end

local function enter_2d(reason)
    local intent=rawget(_G,'AC8_CinematicIntent')
    if (intent and intent.hangarActive)or (AC8Runtime.context.hudName or''):match('^BP_LiveHangarHUD_C ')then return end
    if S.forced then return end
    local cur = mv_get(KEY)
    if cur == nil then
        
        return
    end
    local intent=rawget(_G,'AC8_CinematicIntent')
    S.prev   = (intent and intent.active and intent.saved['VR_2DScreenMode']) or cur
    if intent then intent.guardForced=true end
    S.forced = true
    S.ok_t   = 0
    S.since_force = 0
    local ok = mv_set(KEY, TRUE_S)
    
end

local function exit_2d(reason)
    if not S.forced then return end
    local intent=rawget(_G,'AC8_CinematicIntent')
    if intent and intent.active then return end 
    
    if S.l2 then
        mv_set(METHOD_KEY, S.prev_method or "0")
        
        S.l2 = false
        S.prev_method = nil
    end
    local ok = mv_set(KEY, S.prev or FALSE_S)
    S.forced = false
    if intent then
        intent.guardForced=false
        if intent.persistRestorePending and not intent.active then
            local persisted=pcall(function() uevr.params.vr.save_config() end)
            intent.persistRestorePending=not persisted
        end
    end
    S.ok_t   = 0
    
end

local function pawn_name()
    if not (uevr and uevr.api and uevr.api.get_player_pawn) then return nil end
    local ok, p = pcall(function() return uevr.api:get_player_pawn() end)
    if not ok or p == nil then return nil end
    local ok2, nm = pcall(function() return p:get_full_name() end)
    if not ok2 or type(nm) ~= "string" then return nil end
    return nm
end

local function setup()
    
    local cur = mv_get(KEY)
    if cur == "1" or cur == "0" then
        TRUE_S, FALSE_S = "1", "0"
    end
    

    local r1, r2 = false, false
    pcall(function()
        uevr.sdk.callbacks.on_post_slate_draw_window_render_thread(function()
            S.beats = S.beats + 1
        end)
        r1 = true
    end)
    pcall(function()
        uevr.sdk.callbacks.on_pre_slate_draw_window_render_thread(function()
            S.beats = S.beats + 1
        end)
        r2 = true
    end)
    

    if not (r1 or r2) then
        
    end

    local ok = pcall(function()
        uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
            local intent=rawget(_G,'AC8_CinematicIntent')
            if intent then intent.guardAcknowledged=true;intent.guardForced=S.forced end
            local d = tonumber(delta)
            if d == nil or d <= 0 then d = 1 / 60 end
            if d > 1 then d = 1 end          
            S.T = S.T + d
            S.frames = S.frames + 1

            if S.beats ~= S.seen then
                S.seen  = S.beats
                S.stall = 0
            else
                S.stall = S.stall + d
            end

            if S.hb_ok == nil then
                if S.beats > 0 then
                    S.hb_ok = true
                    
                elseif S.T > 10 then
                    S.hb_ok = false
                    
                end
            end

            local warm = (S.hb_ok == false and S.T > 10)
                      or (S.beats > CFG.WARMUP)

            if CFG.PREVENT and S.frames % CFG.PAWN_EVERY == 0 then
                local nm = pawn_name()
                if nm ~= nil then
                    if S.pawn == nil then
                        S.pawn = nm
                    elseif nm ~= S.pawn then
                        S.pawn = nm

                        if warm and (S.hb_ok == false
                                     or S.stall >= CFG.PREVENT_STALL) then
                            enter_2d("AC8 layout")
                        end
                    end
                end
            end

            if CFG.RESCUE and (not S.forced) and warm
                and S.hb_ok == true and S.stall >= CFG.STALL_SEC then
                S.rescues = S.rescues + 1
                S.last_rescue_t = S.T
                enter_2d(string.format("AC8 layout value=%.1f, value=%d",
                    S.stall, S.rescues))
            end

            if CFG.LEVEL2 and S.forced and (not S.l2) and S.hb_ok == true
                and S.stall >= CFG.LEVEL2_AFTER then
                local cur = mv_get(METHOD_KEY)
                if cur ~= nil and cur ~= MONO_VALUE then
                    S.prev_method = cur
                    S.l2 = true
                    mv_set(METHOD_KEY, MONO_VALUE)
                    
                end
            end

            

            if CFG.RESTORE and S.forced then
                if S.rescues >= CFG.MAX_RESCUE then
                    
                    if S.rescues == CFG.MAX_RESCUE then
                        
                        S.rescues = S.rescues + 1  
                    end
                elseif S.hb_ok == false then
                    
                    S.since_force = S.since_force + d
                    if S.since_force >= 2.0 then
                        exit_2d("AC8 layout")
                    end
                elseif S.stall == 0 then
                    S.ok_t = S.ok_t + d
                    
                    local need = CFG.RESTORE_SEC
                    if S.T - S.last_rescue_t < 15 then need = need * 3 end
                    if S.ok_t >= need then exit_2d("AC8 layout") end
                else
                    S.ok_t = 0
                end
            end
        end)
    end)
    

    S.started = true
end

local ok, err = pcall(setup)
if not ok then
    print(LOG .. "AC8 layout" .. tostring(err))
end

end)(AC8Runtime.host('utility','ac8_cutscene_guard.lua'),AC8Runtime.json,AC8Runtime.log)
end

end
assert(not registry.sections['cinematic'], 'Duplicate AC8 VR section: cinematic')
registry.sections['cinematic'] = function(R)
-- OFF時は完全休眠（レンダースレッド登録ゼロ・Tickゼロ・探索ゼロ）
local cfg = R and R.customHUDConfig and R.customHUDConfig.cinematicPresentation
if not (cfg and cfg.enabled == true) then
    return
end
-- Cinematic and hangar presentation, camera heuristics and transition coverage.

do
-- cinematic intent.
(function(uevr,json,print)

local previous=rawget(_G,'AC8_CinematicIntent')
if previous then error('Cinematic Intent already registered; restart before reloading') end
local S={active=false,maskActive=false,guardForced=false,saved={},elapsed=0,version=26,lensRequested=true,
    authoredProjectionImplemented=false,automaticDetection=true,stereoSeparationUnmodified=true,gameplayExitHoldSeconds=0.25}
_G.AC8_CinematicIntent=S
local function call(o,k,...)
    if not o then return false,'unavailable' end
    return pcall(function(...) return o[k](o,...) end,...)
end
local function value(o,k,...) local ok,v=call(o,k,...);if ok then return v end end
local function full(o) return value(o,'get_full_name') end
local function prop(o,k) return value(o,'get_property',k) end
local function mv(k) local v=value(uevr.params.vr,'get_mod_value',k);if v~=nil then return tostring(v) end end
local screen='VR_2DScreenMode'


local cameraKeys={'VR_CameraForwardOffset','VR_CameraRightOffset','VR_CameraUpOffset'}
local uiKeys={'UI_OverlayType','UI_Distance','UI_Size','UI_FollowView','UI_Y_Offset','UI_X_Offset','UI_Cylinder_Angle'}

local uiDefaults={UI_OverlayType='0',UI_Distance='0.985',UI_Size='1',UI_FollowView='false',UI_Y_Offset='0',UI_X_Offset='0'}
local allKeys={}
for _,k in ipairs(uiKeys) do allKeys[#allKeys+1]=k end
for _,k in ipairs(cameraKeys) do allKeys[#allKeys+1]=k end
local function setUI(k,v)
    local ok=pcall(function() uevr.params.vr.set_mod_value(k,tostring(v)) end)
    local observed=mv(k)
    return ok and (observed==tostring(v) or (tonumber(observed) and tonumber(observed)==tonumber(v)))
end
local function journal(values)
    return pcall(function() json.dump_file('ac8_cinematic_ui_restore.json',{version=1,values=values},2) end)
end

local recovered,backup=pcall(function() return json.load_file('ac8_cinematic_ui_restore.json') end)
if recovered and type(backup)=='table' and backup.version==1 and type(backup.values)=='table' then
    local valid=true
    for _,k in ipairs(uiKeys) do if k~='UI_Y_Offset' and k~='UI_X_Offset' and k~='UI_Cylinder_Angle' and type(backup.values[k])~='string' then valid=false end end
    if valid then for _,k in ipairs(allKeys) do if type(backup.values[k])=='string' then S.saved[k]=backup.values[k] end end;S.recoveringUI=true end
end
-- Recovery can span ticks. Keep saved values/journal until every owned value
-- is restored; other camera/layout services use this as an ownership barrier.
local function restoreUI()
    if next(S.saved)==nil then return true end
    local all=true
    for _,k in ipairs(allKeys) do if S.saved[k] and not setUI(k,S.saved[k]) then all=false end end
    if all then
        if journal({}) then S.saved={};S.recoveringUI=false;S.persistRestorePending=true else all=false end
    end
    ;;return all
end
local function classify(row)
    local hud,cam,target=row.hud or '',row.camera or '',row.viewTarget or ''
    if hud:match('^BP_LiveHangarHUD_C ') and target:match('^BP_HangarCamera_C ') then return 'hangar' end
    local authoredCamera=cam:match('^LiveCineCameraComponent ') or cam:match('^LiveCinematicsCineCameraComponent ')
    local authoredTarget=target:match('^BP_MGC_CineCamera_C ') or target:match('^BP_IGC_CameraPawn_')
    local inMission=target:find('/Game/Maps/IGC/',1,true) or target:find('/Game/Maps/Ingame/',1,true)
    if hud:match('^BP_LiveCinemaHUD_C ') or
        ((hud:match('^LiveMainHUDParent4K_C ') or inMission) and (authoredCamera or authoredTarget)) then
        return 'cinematic'
    end
    if hud:match('^LiveMainHUDParent4K_C ') and cam:match('^LiveFirstPersonCameraComponent ') and target:match('^BP_PlayerPlane_') then return 'gameplay' end
    if hud:match('^BP_LiveMenuHUD_C ') then return 'menu' end
    return 'unknown'
end
local inspectedOwners={}
local function subtitleOwner(hud)
    local name=full(hud)
    if not name or inspectedOwners[name] or not (name:match('^BP_LiveCinemaHUD_C ') or name:match('^LiveMainHUDParent4K_C ')) then return end
    inspectedOwners[name]=true
    local names,refs={},{}
    local c=value(hud,'get_class')
    for depth=1,5 do
        if not c then break end
        c=value(c,'as_class') or c
        local p=value(c,'get_child_properties')
        for i=1,96 do
            if not p then break end
            local n=value(value(p,'get_fname'),'to_string')
            if n and #names<128 then
                names[#names+1]=n
                local lower=n:lower()
                if lower:find('subtitle',1,true) or lower:find('caption',1,true) or lower:find('widget',1,true) then
                    local reference=full(prop(hud,n))
                    if reference then refs[n]=reference end
                end
            end
            p=value(p,'get_next')
        end
        c=value(c,'get_super_struct')
    end
    
end
local missionCache={}
local function missionMatchState(pc)
    local name=full(pc)
    local level=name and name:match('%s(.+%.PersistentLevel)%.')
    if not level then return nil end
    if missionCache.level==level and S.elapsed<(missionCache.untilTime or 0) then return missionCache.value end
    missionCache={level=level,untilTime=S.elapsed+0.5}
    local cls=value(uevr.api,'find_uobject','Class /Script/Live.LiveGameState')
    local states=value(cls,'get_objects_matching',false)
    if type(states)~='table' then return nil end
    for _,state in ipairs(states) do
        local stateName=full(state)
        local stateLevel=stateName and stateName:match('%s(.+%.PersistentLevel)%.')
        if stateLevel==level then
            local v=prop(state,'MatchState')
            missionCache.value=type(v)=='string' and v or value(v,'to_string')
            return missionCache.value
        end
    end
end
local function camera()
    local pc=value(uevr.api,'get_player_controller',0)
    if not pc then pc=prop(value(uevr.api,'get_player_pawn'),'Controller') end
    local pm=prop(pc,'PlayerCameraManager')
    local hud=value(pc,'GetHUD')
    subtitleOwner(hud)
    local vt=value(pc,'GetViewTarget') or value(pm,'GetViewTarget')
    local component=prop(vt,'CameraComponent') or prop(vt,'CineCameraComponent')
    if not component then
        local c=value(uevr.api,'find_uobject','Class /Script/Engine.CameraComponent')
        if c then component=value(vt,'GetComponentByClass',c) end
    end
    return {controller=full(pc),cinematicMode=prop(pc,'bCinematicMode'),hud=full(hud),
        viewTarget=full(vt),camera=full(component),cameraManager=full(pm),
        fov=value(pm,'GetFOVAngle'),componentFOV=prop(component,'FieldOfView'),
        aspectRatio=prop(component,'AspectRatio'),constrainAspect=prop(component,'bConstrainAspectRatio'),
        focalLength=prop(component,'CurrentFocalLength'),screenMode=mv(screen),missionMatchState=missionMatchState(pc)}
end
local function mask(on)
    local data=on and ('on|'..S.saved.UI_Size..'|'..S.saved.UI_Distance) or 'off'
    return pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicMask',data) end)
end
local function shotOverrides(on,mode)
    if S.shotOverridesActive==on then return end
    if not on then pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicLensMode','off') end) end
    local ok=pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicCamera',on and 'on' or 'off') end)
    if not ok then return end
    S.shotOverridesActive=on;S.cameraLocked=on
    if on and S.lensRequested and S.nativeProjectionReady then
        pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicLensMode','on') end)
    end
    
end
local function exit(reason)
    if not S.maskActive and next(S.saved)==nil then return end
    pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicLensMode','off') end)
    pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicCamera','off') end)
    mask(false);S.maskActive=false;S.cameraLocked=false;S.shotOverridesActive=false;S.automaticSession=false
    if reason=='manual' or reason=='F7' then S.suppressCurrentChain=true end
    local restored=restoreUI()

end
local function enter(automatic)
    if S.maskActive then return end
    if not S.nativeMaskReady then ;return end
    if next(S.saved)~=nil and not restoreUI() then return end
    if not S.nativeCameraReady or mv('VR_RenderingMethod')~='0' then return end
    local saved={}
    for _,k in ipairs(allKeys) do
        saved[k]=mv(k)
        if not saved[k] or saved[k]=='' then return end
    end
    if not tonumber(saved.UI_Size) or not tonumber(saved.UI_Distance) then return end
    if not journal(saved) then return end
    S.saved=saved
    for _,k in ipairs(uiKeys) do
        local v=uiDefaults[k] or saved[k] 
        if k=='UI_FollowView' and (saved[k]=='0' or saved[k]=='1') then v='0' end
        if not setUI(k,v) then restoreUI();;return end
    end
    for _,k in ipairs(cameraKeys) do
        if not setUI(k,'0') then restoreUI();;return end
    end
    local lockOK=pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicCamera','on') end)
    if not lockOK then restoreUI();;return end
    if not mask(true) then pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicCamera','off') end);restoreUI();;;return end
    S.maskActive=true;S.cameraLocked=true;S.shotOverridesActive=true;S.startedAt=S.elapsed;S.automaticSession=automatic==true
    if S.lensRequested and S.nativeProjectionReady then pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicLensMode','on') end) end
    
    
end

S.hangarSaved={}
local hk,hj=pcall(function()return json.load_file('ac8_hangar_restore_v48.json')end)
if hk and type(hj)=='table' and type(hj.values)=='table' then
    for _,k in ipairs(cameraKeys)do if type(hj.values[k])=='string' then S.hangarSaved[k]=hj.values[k]end end
end
local function recoverOldHangar()
    if next(S.hangarSaved)==nil then return true end
    local restored=true
    for _,k in ipairs(cameraKeys)do if S.hangarSaved[k] and not setUI(k,S.hangarSaved[k])then restored=false end end
    if restored and pcall(function()json.dump_file('ac8_hangar_restore_v48.json',{values={}},2)end)then S.hangarSaved={} else restored=false end
    return restored
end
local function hangar(on)
    if on and not S.hangarActive then
        if not recoverOldHangar()then return end
        if S.maskActive then exit('enter-hangar')end
        if not S.nativeCameraReady or not S.nativeMaskReady or mv('VR_RenderingMethod')~='0'then return end
        local saved={};for _,k in ipairs(cameraKeys)do saved[k]=mv(k);if not saved[k]then return end end
        if not pcall(function()json.dump_file('ac8_hangar_restore_v48.json',{values=saved},2)end)then return end
        S.hangarSaved=saved
        local all=true;for _,k in ipairs(cameraKeys)do if not setUI(k,'0')then all=false end end
        if not all then recoverOldHangar();return end
        local size,distance=mv('UI_Size'),mv('UI_Distance')
        if not tonumber(size)or not tonumber(distance)then recoverOldHangar();return end
        local ok=pcall(function()
            uevr.api:dispatch_custom_event('AC8_CinematicFullView','off')
            uevr.api:dispatch_custom_event('AC8_CinematicCamera','on')
            uevr.api:dispatch_custom_event('AC8_HangarCrop','on|'..size..'|'..distance)
            uevr.api:dispatch_custom_event('AC8_CinematicLensMode',S.lensRequested and S.nativeProjectionReady and 'on'or'off')
        end)
        if not ok then recoverOldHangar();;return end
        S.hangarActive=true;S.hangarUsesCinematicWindow=true;S.hangarFullViewMovie=false;S.shotOverridesActive=true;S.cameraLocked=true
        
    elseif not on and S.hangarActive then
        pcall(function()uevr.api:dispatch_custom_event('AC8_HangarCrop','off');uevr.api:dispatch_custom_event('AC8_CinematicFullView','off');uevr.api:dispatch_custom_event('AC8_CinematicCamera','off');uevr.api:dispatch_custom_event('AC8_CinematicLensMode','off')end)
        S.hangarActive=false;S.hangarUsesCinematicWindow=false;S.shotOverridesActive=false;S.cameraLocked=false
        local restored=recoverOldHangar();S.persistRestorePending=restored
        
    elseif not on and next(S.hangarSaved)~=nil then recoverOldHangar()end
end
local togglePending=false

local function authoredPose()
    local pc=value(uevr.api,'get_player_controller',0)
    local target=value(pc,'GetViewTarget')
    local component=prop(target,'CameraComponent') or prop(target,'CineCameraComponent')
    if not component then
        local cls=value(uevr.api,'find_uobject','Class /Script/Engine.CameraComponent')
        component=cls and value(target,'GetComponentByClass',cls)
    end
    local name=full(component) or ''
    if not (name:match('^LiveCineCameraComponent ') or name:match('^LiveCinematicsCineCameraComponent ')) then
        S.authoredPoseState='camera-component-not-verified';return
    end
    local location=value(component,'K2_GetComponentLocation')
    local rotation=value(component,'K2_GetComponentRotation')
    local ok,values=pcall(function()return {location.X,location.Y,location.Z,rotation.Pitch,rotation.Yaw,rotation.Roll}end)
    if not ok then S.authoredPoseState='component-pose-unavailable';return end
    for i=1,6 do if type(values[i])~='number' or values[i]~=values[i] then S.authoredPoseState='invalid-component-pose';return end end
    local parts={};for i=1,6 do parts[i]=string.format('%.17g',values[i])end
    local sent=pcall(function()uevr.api:dispatch_custom_event('AC8_AuthoredCameraPose',table.concat(parts,'|'))end)
    S.authoredPoseState=sent and 'component-pose-sent' or 'component-pose-send-failed';S.authoredPoseComponent=name
    if S.hangarActive then S.hangarAuthoredPose=values end
end
uevr.sdk.callbacks.on_lua_event(function(name,data)
end)
S.lensCallbackRegistered=pcall(function()
    uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(function()
        if not S.shotOverridesActive or not (S.maskActive or S.hangarActive) then return end
        authoredPose()
        if not (S.maskActive or S.hangarUsesCinematicWindow) or not S.lensRequested then return end
        local ok,row=pcall(camera)
        if ok and type(row.fov)=='number' and type(row.aspectRatio)=='number' then
            pcall(function()uevr.api:dispatch_custom_event('AC8_CinematicLens',tostring(row.fov)..'|'..tostring(row.aspectRatio))end)
            S.renderLens={fov=row.fov,aspect=row.aspectRatio}
        end
    end)
end)
local registered=pcall(function()
    uevr.sdk.callbacks.on_lua_event(function(name,data)
        if name=='AC8_CinematicProjection_Ready' and S.lensCallbackRegistered then
            S.nativeProjectionReady=true
            if (S.maskActive or S.hangarUsesCinematicWindow) and S.shotOverridesActive and S.lensRequested then
                pcall(function() uevr.api:dispatch_custom_event('AC8_CinematicLensMode','on') end)
            end
        end
        if name=='AC8_CinematicCamera_Ready' then S.nativeCameraReady=true end
        if name=='AC8_CinematicMask_Ready' and not S.nativeMaskReady then S.nativeMaskReady=true; end
        if name=='AC8_CinematicMask_Failed' then S.nativeMaskReady=false;exit('native-mask-failed') end
        if name=='AC8_CinematicIntent_F7' then
            togglePending=true
            
        end
    end)
end)
S.hotkeyCallbackRegistered=registered
local nextCameraCheck=0
local terminalMode,terminalSince=nil,nil
local function command()
    local ok,row=pcall(function() return json.load_file('ac8_cinematic_intent_control.json') end)
    if ok and type(row)=='table' then return row end
end
local initialCommand=command()
local lastCommand=initialCommand and initialCommand.revision
local nextControl=0
uevr.sdk.callbacks.on_pre_engine_tick(function(engine,delta)
    if not S.maskActive and next(S.saved)~=nil and S.elapsed>=(S.nextRestoreAttempt or 0) then
        restoreUI();S.nextRestoreAttempt=S.elapsed+2
    end
    if not S.maskActive and not S.hangarActive and S.persistRestorePending and not S.guardForced then
        if pcall(function() uevr.params.vr.save_config() end) then S.persistRestorePending=false end
    end
    S.elapsed=S.elapsed+math.max(0,math.min(tonumber(delta) or 0.016,1))
    if S.shotOverridesActive and (S.maskActive or S.hangarActive) then
        local all=true
        for _,k in ipairs(cameraKeys)do if tonumber(mv(k))~=0 and not setUI(k,'0')then all=false end end
        S.cameraOffsetsHeldZero=all
    else S.cameraOffsetsHeldZero=false end
    if S.elapsed>=nextControl then
        nextControl=S.elapsed+0.25
        local request=command()
        if request and type(request.revision)=='string' and request.revision~=lastCommand then
            lastCommand=request.revision
            if request.action=='toggle' then togglePending=true end
            
            S.controlRevision=lastCommand
        end
    end
    if togglePending then
        togglePending=false
        if S.maskActive then exit('F7') else enter() end
    end
    if S.maskActive and not S.automaticSession and S.elapsed-S.startedAt>=180 then exit('manual-timeout') end
    if S.elapsed>=nextCameraCheck then
        local ok,row=pcall(camera)
        if ok then
            S.camera=row
            local mode=classify(row)
            hangar(mode=='hangar')

            if S.maskActive and S.automaticDetection and S.automaticSession then shotOverrides(mode=='cinematic' or mode=='hangar',mode) end

            if mode=='gameplay' and row.missionMatchState and row.missionMatchState~='InProgress' then mode='unknown' end
            S.detectedMode=mode
            if mode=='gameplay' or mode=='menu' then
                if mode~=terminalMode then
                    terminalMode=mode;terminalSince=S.elapsed
                    if S.maskActive then  end
                end

                local wait=mode=='gameplay' and (row.missionMatchState=='InProgress' and 0.1 or S.gameplayExitHoldSeconds) or 1.5
                if S.elapsed-terminalSince>=wait then
                    S.suppressCurrentChain=false
                    if S.maskActive then exit('auto-return-'..mode) end
                end
            else
                if terminalMode and S.maskActive then
                    
                end
                terminalMode=nil;terminalSince=nil
                if mode=='cinematic' and S.automaticDetection and not S.suppressCurrentChain and not S.maskActive then enter(true) end
                if mode=='cinematic' and S.maskActive and S.automaticDetection then S.automaticSession=true end
            end
            
        end
        nextCameraCheck=S.elapsed+0.1
    end
end)

end)(AC8Runtime.host('presentation','ac8_cinematic_intent.lua'),AC8Runtime.json,AC8Runtime.log)
end

do
-- hangar coverage.
(function(uevr,json,print)

local last=nil;local ticks=0
uevr.sdk.callbacks.on_pre_engine_tick(function()
 ticks=ticks+1;if ticks%30~=1 then return end
 local x,y=1.25,1.25;local ok,v=pcall(function()return json.load_file('ac8_hangar_coverage_controls.json')end)
 if ok and type(v)=='table' then
  if type(v.horizontal)=='number' and v.horizontal>=1 and v.horizontal<=3 then x=v.horizontal end
  if type(v.vertical)=='number' and v.vertical>=1 and v.vertical<=2 then y=v.vertical end
 end
 local packet=tostring(x)..'|'..tostring(y)
 if packet~=last then uevr.api:dispatch_custom_event('AC8_HangarCoverage',packet);last=packet end
end)

end)(AC8Runtime.host('presentation','ac8_hangar_coverage.lua'),AC8Runtime.json,AC8Runtime.log)
end


end

if registry.start then registry.start() end
