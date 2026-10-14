-- Shorten allowlisted startup notices and seek only known startup/menu movies.
-- Temporary timing changes retain restoration baselines. Scanning stops after
-- 90 engine seconds; normal mission/tutorial movie playback is not selected.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['startup_movies'], 'Duplicate AC8 VR section: startup_movies')
registry.sections['startup_movies'] = function(R)
-- Speed up only the authored startup notices/movies; restore temporary owned timings.

do
-- Allowlisted startup timing and native movie seek.
(function(uevr,json,print)


local function call(o,k,...)
    if not o then return false,'object unavailable' end
    return pcall(function(...) return o[k](o,...) end,...)
end
local function value(o,k,...)
    local ok,v=call(o,k,...);if ok then return v end
end
local function full(o) return value(o,'get_full_name') end
local function field(o,k) local ok,v=pcall(function() return o[k] end);if ok then return v end end
local function find(n) return value(uevr.api,'find_uobject',n) end
local fields={'FadeInTime','FadedInWaitTime','FadedInCanSkipAfterTime','FadeOutTime','FadedOutTime'}
local classes={
 'Class /Script/Live.LiveMenuNoticeScreenContentWidget',
 'Class /Script/Live.LiveMenuNoticeScreenMovieContentWidget'
}
local settingName='LiveMenuNoticeScreenSetting /Game/Datatables/UI/Menu/MainMenu/NoticeScreen/DA_LiveMenuNoticeScreenSetting.DA_LiveMenuNoticeScreenSetting'
local allowed={['001']=true,['003']=true,['004_01']=true,['004_02']=true,['005']=true,['006']=true,['007']=true}
local report={version=3,status='watching',maxStageSeconds=0.05}
local originals,attempted={},{}
local elapsed,nextScan=0,0
local done=false

local function restoreOne(n,reason)
    local old=originals[n];if not old then return end
    local o=find(n)
    if not o then originals[n]=nil;return end
    local all=true
    for k,v in pairs(old) do
        local ok=call(o,'set_property',k,v)
        if not ok or value(o,'get_property',k)~=v then all=false end
    end
    
    if all then originals[n]=nil end
end
local function apply(o,keys)
    local n=full(o)
    if not n or attempted[n] then return end
    attempted[n]=true
    local old,wanted={},{}
    for _,k in ipairs(keys) do
        local v=value(o,'get_property',k)
        if type(v)~='number' or v~=v or v<0 or v>120 then return end
        old[k]=v;wanted[k]=math.min(v,0.05)
    end
    originals[n]=old
    local verified=true
    for _,k in ipairs(keys) do
        local ok=call(o,'set_property',k,wanted[k])
        if not ok or math.abs((value(o,'get_property',k) or -1)-wanted[k])>0.00001 then verified=false;break end
    end
    
    if not verified then restoreOne(n,'write-verification-failed') end
end
local movieAllow={
 ['FileManaMovie /Game/SofdecMovies/UI/Title/MS_Title_AcesLogo.MS_Title_AcesLogo']={target='aces-logo',owner='.WBP_Menu_NoticeScreenWidget_000_C_',child='.WBP_NoticeScreenWidget_007_C_'},
 ['FileManaMovie /Game/SofdecMovies/UI/Menu/Transition/MS_Menu_Transition_Open.MS_Menu_Transition_Open']={target='menu-opening',owner='.WBP_LiveMenuMovieTransitionWidget_C_'},
 ['FileManaMovie /Game/SofdecMovies/UI/Menu/Transition/MS_Menu_Transition_Kirikae_A_Pattern4.MS_Menu_Transition_Kirikae_A_Pattern4']={target='menu-transition-pattern4',owner='.WBP_LiveMenuMovieTransitionWidget_C_'}
}
local stopped,started={},{}
local function scanMovies()
    local c=find('Class /Script/Live.LiveManaMovieViewer');c=value(c,'as_class') or c
    for _,viewer in ipairs(value(c,'get_objects_matching',false) or {}) do
        local vn=full(viewer) or ''
        if vn:find('/Engine/Transient.',1,true) then
            local sn=full(value(viewer,'get_property','PlayingManaSource'))
            local player=value(viewer,'get_property','ManaPlayer')
            local ready,playing=value(player,'IsReady'),value(player,'IsPlaying')
            local rule=movieAllow[sn]
            if rule and ready==true and playing==true and not started[vn] then started[vn]=elapsed end
            if rule and not stopped[sn] and vn:find(rule.owner,1,true) and (not rule.child or vn:find(rule.child,1,true)) and ready==true and playing==true and started[vn] and elapsed-started[vn]>=0.5 then
                
                stopped[sn]=true
                local supportedOK,supported=call(player,'SupportsSeeking')
                local durationOK,duration=call(player,'GetDuration')
                if supportedOK and supported==true and durationOK and duration~=nil then
                    call(player,'Seek',duration)
                end
            end
        end
    end

end
local function scan()
    local setting=find(settingName)
    if setting then apply(setting,{'FinishWaitTime'}) end
    for _,path in ipairs(classes) do
        local c=find(path);c=value(c,'as_class') or c
        for _,o in ipairs(value(c,'get_objects_matching',false) or {}) do
            local n=full(o) or ''
            local id=n:match('^WBP_NoticeScreenWidget_(%d+_?%d*)_C ')
            if allowed[id] and n:find('/Engine/Transient.',1,true) and n:find('.WBP_Menu_NoticeScreenWidget_000_C_',1,true) then apply(o,fields) end
        end
    end
    scanMovies()
end

local function finishStartup(reason)
    if done then return end
    done = true
    report.status = 'flight-terminated'
    print(string.format('[AC8-STARTUP] Flight detected: Startup movie scan permanently stopped (%s, elapsed=%.1fs)', tostring(reason), elapsed))
end

uevr.sdk.callbacks.on_post_engine_tick(function(engine,delta)
    if done then return end
    elapsed=elapsed+math.max(0,math.min(tonumber(delta) or 0.016,1))

    -- When entering actual flight, completely and permanently stop all scanning
    local ctx = rawget(_G, 'AC8Runtime') and AC8Runtime.context
    if ctx and (ctx.flight or (ctx.hudName or ''):match('^LiveMainHUDParent4K_C')) then
        finishStartup('entered-flight')
        return
    end

    -- During startup / menu: maintain responsive 0.05s scan to instantly skip logos and notices
    if elapsed >= nextScan then
        pcall(scan)
        nextScan = elapsed + 0.05
    end
end)

end)(AC8Runtime.host('intro','AC8_VR-StartupMovies.lua'),AC8Runtime.json,AC8Runtime.log)
end

end

if registry.start then registry.start() end
