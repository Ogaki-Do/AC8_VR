-- Resolve the current game-instance loading screen and native fade widget.
-- Check both pre/post engine phases so a newly created flight HUD cannot uncover
-- the map early. A persistent loading-icon root alone is not a loading signal.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['mission_loading'], 'Duplicate AC8 VR section: mission_loading')
registry.sections['mission_loading'] = function(R)
do
-- the current loading subsystem owns the actual mission-loading screen.
-- Captured native UI is not in the viewport. The persistent status-icon root
-- alone must never count as loading. No widget setters or pixel tests.
local R=AC8Runtime
local S={version=85,nextScan=0,active=false,reason='waiting'}
R.missionLoading=S
local function call(o,k,...)
 if not o or(o~=uevr.api and not R.isLiveObject(o))then return end
 local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function full(o)return call(o,'get_full_name')end
local function prop(o,k)return call(o,'get_property',k)end
local function clear(reason)S.active=false;S.screen=nil;S.screenName=nil;S.reason=reason end
local function visible(o)
 local v=call(o,'GetVisibility');local a=call(o,'GetRenderOpacity')
 return type(v)=='number'and v~=1 and v~=2 and type(a)=='number'and a==a and a>0
end
local statics
local function update()
 if R.context.flight and not S.active then return end
 if not R.isLiveObject(statics)then statics=call(uevr.api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics')end
 local gi=call(statics,'GetGameInstance',R.context.pc);local gin=full(gi)
 if not gin then S.subsystem=nil;S.gameInstance=nil;S.nextScan=0;clear('no current game instance');return end
 if gin~=S.gameInstance then S.gameInstance=gin;S.subsystem=nil;S.nextScan=0 end
 if S.subsystem and (not R.isLiveObject(S.subsystem)or full(call(S.subsystem,'get_outer'))~=gin)then S.subsystem=nil;S.nextScan=0 end
 if not S.subsystem and R.tick>=S.nextScan then
  S.nextScan=R.tick+60
  local cls=call(uevr.api,'find_uobject','Class /Script/Live.LiveLoadingScreenSubsystem')
  for i,o in ipairs(call(cls,'get_objects_matching',false)or{})do
   if i>8 then break end
   local n=full(o)
   if n and n:match('^LiveLoadingScreenSubsystem ')and not n:find('Default__',1,true)and full(call(o,'get_outer'))==gin then S.subsystem=o;break end
  end
 end
 if not S.subsystem then clear('no current loading subsystem');return end
 local root=prop(S.subsystem,'LoadingScreenRootWidget')
 if not(full(root)or''):match('^WBP_Loading_Root_000_C ')or full(call(root,'get_outer'))~=gin then clear('no owned loading root');return end
 local screen=prop(root,'LoadingScreen');local name=full(screen)
 -- Narrow to the observed mission manager; startup, save/connect and other
 -- loading-screen types keep their existing behavior.
 if not(name or''):match('^WBP_MissionLoad_ManagerWidget_000_C ')or full(call(screen,'get_outer'))~=gin then clear('no mission loading screen');return end
 local panel=prop(root,'RootPanel');local panelName=full(panel)
 if not panelName or full(call(screen,'GetParent'))~=panelName then clear('mission screen detached');return end
 local current=screen;local seen={}
 for _=1,16 do
  local n=full(current)
  if not n or seen[n]or not visible(current)then clear('mission screen hidden or stale');return end
  seen[n]=true
  if n==full(root)then S.active=true;S.screen=screen;S.screenName=name;S.reason='owned visible mission loading screen';return end
  local parent=call(current,'GetParent')
  if not parent then
   local outer=call(current,'get_outer')
   if(full(outer)or''):match('^WidgetTree ')then parent=call(outer,'get_outer')end
  end
  if not parent then clear('mission screen chain detached');return end
  local selected=call(parent,'GetActiveWidget')
  if selected and full(selected)~=n then clear('inactive loading branch');return end
  current=parent
 end
 clear('loading hierarchy too deep')
end
local host=R.host('utility','mission loading ownership')
host.sdk.callbacks.on_pre_engine_tick(update)
end


end
assert(not registry.sections['transitions'], 'Duplicate AC8 VR section: transitions')
registry.sections['transitions'] = function(R)
do
-- vr transitions.
(function(uevr,json,print)


local api=uevr.api
local old=rawget(_G,'AC8VRTransitions');if old then old.stopped=true end
local S={version=76,stopped=false,ticks=0,elapsed=0,nextScan=0,sources={},loading=false,opacity=0}
rawset(_G,'AC8VRTransitions',S)
local function call(o,k,...)
    if not o or(o~=api and not AC8Runtime.isLiveObject(o))then return nil end
    local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function full(o)return call(o,'get_full_name')end
local function prop(o,k)return call(o,'get_property',k)end
local function color(v)
    local r,g,b,a=field(v,'R'),field(v,'G'),field(v,'B'),field(v,'A')
    if type(r)=='number' and type(g)=='number' and type(b)=='number' and type(a)=='number' and r==r and g==g and b==b and a==a then
        return {math.max(0,math.min(1,r)),math.max(0,math.min(1,g)),math.max(0,math.min(1,b)),math.max(0,math.min(1,a))}
    end
end
local function parent(w)
    local p=call(w,'GetParent');if p then return p end
    local outer=call(w,'get_outer');if (full(outer) or ''):match('^WidgetTree ')then return call(outer,'get_outer')end
end
local function opacity(w)
    local result,seen=1,{}
    for _=1,32 do
        local n=full(w);if not n or seen[n]then return 0 end;seen[n]=true
        local v=call(w,'GetVisibility');local a=call(w,'GetRenderOpacity')
        if type(v)~='number' or v==1 or v==2 or type(a)~='number' or a<=0 then return 0 end
        result=result*math.min(1,a)
        local p=parent(w);if not p then return result end
        local active=call(p,'GetActiveWidget');if active and full(active)~=n then return 0 end;w=p
    end
    return 0
end
local slate=call(call(api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary'),'get_class_default_object')
local function xy(v)
    local x,y=field(v,'X'),field(v,'Y');if type(x)=='number' and type(y)=='number' and x==x and y==y then return {X=x,Y=y}end
end
local function rect(w,root)
    local g=call(w,'GetPaintSpaceGeometry') or call(w,'GetCachedGeometry')
    local rg=call(root,'GetPaintSpaceGeometry') or call(root,'GetCachedGeometry')
    local size,rs=xy(call(slate,'GetLocalSize',g)),xy(call(slate,'GetLocalSize',rg))
    if not size or not rs or rs.X<=0 or rs.Y<=0 then return {0,0,1,1}end
    local a=xy(call(slate,'AbsoluteToLocal',rg,call(slate,'LocalToAbsolute',g,{X=0,Y=0})))
    local b=xy(call(slate,'AbsoluteToLocal',rg,call(slate,'LocalToAbsolute',g,size)))
    if not a or not b then return {0,0,1,1}end
    local r={math.max(0,a.X/rs.X),math.max(0,a.Y/rs.Y),math.min(1,b.X/rs.X),math.min(1,b.Y/rs.Y)}
    if r[3]-r[1]<0.5 or r[4]-r[2]<0.5 then return nil end 
    return r
end
local function discover()
    S.sources={};S.weaponMenus={}
    local widgets=call(call(api,'find_uobject','Class /Script/UMG.UserWidget'),'get_objects_matching',false) or {}
    for i,w in ipairs(widgets)do
        if i>8192 then break end
        local n=full(w) or ''
        local cls=(n:match('^(%S+)') or ''):lower()
        if cls:find('menu',1,true) and (cls:find('weapon',1,true) or cls:find('aircrafttree',1,true) or cls:find('aircraft_tree',1,true) or cls:find('development',1,true) or cls:find('tech_tree',1,true)) then S.weaponMenus[#S.weaponMenus+1]=w end
        if n:find('/Engine/Transient.',1,true) and (n:match('^WBP_NUIFader_C ') or n:match('^LiveNUIFaderWidget '))then
            local image=prop(w,'FadeImage')
            if image then S.sources[#S.sources+1]={widget=w,image=image,name=full(image),owner=n,animation=prop(w,'FadeAnim')}end
        end
    end
end
local gameStateStatics
local function stateValue(state)
    local v=prop(state,'MatchState');return type(v)=='string' and v or call(v,'to_string')
end
local function matchState(pc)
    local level=(full(pc) or ''):match('%s(.+%.PersistentLevel)%.')
    if not level then return nil end
    -- Cache only the static helper, never the world's selected GameState.
    -- Ask the current world each pre/post tick so same-world replacements and
    -- WaitingToStart changes are observed immediately, even if old actors live.
    if not AC8Runtime.isLiveObject(gameStateStatics)then
        gameStateStatics=call(api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics')
    end
    local current=call(gameStateStatics,'GetGameState',pc)
    local name=full(current)or''
    if name:match('^LiveGameState ')and name:find(' '..level..'.',1,true)then
        local value=stateValue(current)
        if value~=nil then
            S.ownerStateReads=(S.ownerStateReads or 0)+1
            return value
        end
    end
    -- Preserve the previous discovery behavior when reflection, type, owner or
    -- MatchState is unavailable. Do not cache absence or delay a later retry.
    S.stateFallbackScans=(S.stateFallbackScans or 0)+1
    for _,state in ipairs(call(call(api,'find_uobject','Class /Script/Live.LiveGameState'),'get_objects_matching',false) or {})do
        if (full(state) or ''):find(level..'.',1,true)then
            return stateValue(state)
        end
    end
end
local function update(_,delta)
    if S.stopped then return end;S.ticks=S.ticks+1;S.elapsed=S.elapsed+math.max(0,math.min(tonumber(delta) or 0.016,1))
    local isFlight = AC8Runtime and AC8Runtime.context and AC8Runtime.context.flight
    local scanInterval = isFlight and 10.0 or 1.0
    if S.elapsed>=S.nextScan then discover();S.nextScan=S.elapsed+scanInterval end
    local pc=call(api,'get_player_controller',0);local hud=call(pc,'GetHUD');local hn=full(hud) or '';local pn=full(pc) or ''
    local state=matchState(pc)

    local loading=pn:find('/Game/Maps/Transition/',1,true)~=nil or
        (hn:match('^LiveMainHUDParent4K_C ')~=nil and state=='WaitingToStart')
    local missionLoading=AC8Runtime.missionLoading.active
    if missionLoading then loading=true end
    local alpha,rgb,region,source=0,{0,0,0},{0,0,1,1},nil
    local main=prop(hud,'HudWidget')

    local nativeSource=0;local nativeMultiplier=1
    if not isFlight or S.ticks%15==0 or not S.cachedFadeWidgets then
        local fadeClass=call(api,'find_uobject','Class /Script/Live.LiveFadeWidget')
        S.cachedFadeWidgets = call(fadeClass,'get_objects_matching',false) or {}
    end
    for _,w in ipairs(S.cachedFadeWidgets or {})do
        local n=full(w) or '';local active=n:match('^LiveFadeWidget ') and call(w,'IsInViewport')==true and opacity(w)>0
        
        local ci=rawget(_G,'AC8_CinematicIntent')
        -- Cropped movies already cover their surround. Private paint alpha is
        -- unknown; viewport registration alone must not force a black frame.
        if active and not(ci and(ci.maskActive or ci.hangarActive))and nativeSource==0 then nativeSource=call(w,'get_address')or 0;nativeMultiplier=opacity(w)end
    end
    for _,row in ipairs(S.sources)do
        if full(row.image)==row.name then
            local tint=color(call(row.image,'GetBrushColor') or prop(row.image,'BrushColor')) or
                color(call(row.image,'GetColorAndOpacity') or prop(row.image,'ColorAndOpacity'))
            local playing=row.animation and call(row.widget,'IsAnimationPlaying',row.animation)==true
            local a=playing and tint and tint[4]*opacity(row.image) or 0
            
            if a>alpha then
                local root=main
                if not root then root=row.widget;for _=1,24 do local p=parent(root);if not p then break end;root=p end end
                local bounds=rect(row.image,root)
                if bounds then alpha=a;region=bounds;source=row.name end
            end
        end
    end
    local pm=prop(pc,'PlayerCameraManager')
    local cameraFade=prop(pm,'FadeAmount');local fadeEnabled=prop(pm,'bEnableFading')
    if fadeEnabled==true and type(cameraFade)=='number' and cameraFade>alpha and cameraFade<=1 then alpha=cameraFade;source='PlayerCameraManager.FadeAmount'end

    if hn:match('^BP_LiveMenuHUD_C ')then alpha=1;source='menu-black-surround'end
    for _,w in ipairs(S.weaponMenus or {})do
        local current=w;local live=false
        for _=1,24 do if not current then break end;if call(current,'IsInViewport')==true then live=true;break end;current=parent(current)end
        if live and opacity(w)>0 then alpha=1;loading=true;source='weapon-tree-black-background';break end
    end
    if loading then alpha=1;rgb={0,0,0}end
    -- A native partial fade must not release the scene cover underneath the
    -- still-visible mission loading screen. Restore the ordinary fade source
    -- immediately when that owned screen clears; exit-fade math is unchanged.
    if missionLoading then nativeSource=0;nativeMultiplier=1;source='owned-mission-loading-screen'end

    local nativePacket=string.format('%.0f|%.9g',nativeSource,nativeMultiplier)
    if nativePacket~=S.nativePacket then api:dispatch_custom_event('AC8_NativeFadeSource',nativePacket);S.nativePacket=nativePacket end
    local packet={string.format('%.8g',alpha),loading and '1' or '0'}
    for _,v in ipairs(rgb)do packet[#packet+1]=string.format('%.8g',v)end
    for _,v in ipairs(region)do packet[#packet+1]=string.format('%.8g',v)end
    pcall(function()api:dispatch_custom_event('AC8_TransitionCover',table.concat(packet,'|'))end)

    S.loading=loading;S.opacity=alpha;S.source=source;S.matchState=state;S.bounds=region;S.hud=hn
    
end
uevr.sdk.callbacks.on_pre_engine_tick(update)

end)(AC8Runtime.host('utility','general_vr_transitions.lua'),AC8Runtime.json,AC8Runtime.log)
end

end

if registry.start then registry.start() end
