-- Publish widget policy rectangles and control glow across flight/menu/loading changes.
-- Preserve geometry/visibility/clip ownership when building policy. Full heartbeat
-- packets continue even when cached serialization can be reused.
-- See source_code/MAINTAINERS.md for ownership and update rules.
-- AC8 VR: register sections; Core starts them in explicit dependency order.
-- Filenames need no numeric prefixes. Keep the complete public script set together.
local registry = rawget(_G, 'AC8VRModules')
if not registry then
 registry = {sections={}, state='waiting', completed={}}
 rawset(_G, 'AC8VRModules', registry)
end
assert(not registry.sections['glow_lifecycle'], 'Duplicate AC8 VR section: glow_lifecycle')
registry.sections['glow_lifecycle'] = function(R)
do
-- ac8 glow lifecycle
(function(uevr,json,print)

local lastFlight,lastPaused=nil,nil
local lastMission,lastMissionLevel=nil,nil
local statics=nil
local function invoke(o,k,...)
    if not o then return nil end
    local ok,v=pcall(function(...) return o[k](o,...) end,...)
    if ok then return v end
end
local function dispatch(data)
    pcall(function() uevr.api:dispatch_custom_event('AC8_HUD_GlowLifecycle',data) end)
end
local function level(name)
    
    return name:match('^%S+ (.+%.PersistentLevel)%.') or name:match('^%S+ (.+)%.[^%.]+$')
end
local function update()
    local pc=invoke(uevr.api,'get_player_controller',0)
    local hud=invoke(pc,'GetHUD')
    local name=invoke(hud,'get_full_name') or ''
    if not statics then statics=invoke(uevr.api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics') end
    local paused
    if pc then paused=invoke(statics,'IsGamePaused',pc) end
    local actualFlight=name:match('^LiveMainHUDParent4K_C ')~=nil
    local hudLevel=level(name)
    local pausedMission=paused==true and lastFlight==true and
        (name=='' or (hudLevel~=nil and hudLevel==lastMissionLevel))
    local flight=(actualFlight or pausedMission)and not AC8Runtime.missionLoading.active
    if flight~=lastFlight then dispatch(flight and 'flight' or 'outside_flight');lastFlight=flight end
    if actualFlight then
        local controller=invoke(pc,'get_full_name')
        local mission=controller and controller..'|'..(hudLevel or name)
        if mission and mission~=lastMission then lastMission=mission;dispatch('mission_entry') end
        lastMissionLevel=hudLevel
    elseif name:match('^BP_LiveMenuHUD_C ') and not pausedMission then
        lastMission,lastMissionLevel=nil,nil
    end
    if type(paused)=='boolean' then
        if lastPaused~=nil and paused~=lastPaused and flight then dispatch(paused and 'pause_enter' or 'pause_exit') end
        lastPaused=paused
    end
end
uevr.sdk.callbacks.on_pre_engine_tick(update)
uevr.sdk.callbacks.on_post_engine_tick(update)

end)(AC8Runtime.host('utility','ac8_glow_lifecycle.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['hud_policy'], 'Duplicate AC8 VR section: hud_policy')
registry.sections['hud_policy'] = function(R)
do
-- hud policy.
(function(uevr,json,print)


local api=uevr.api
local old=rawget(_G,'AC8HudPolicyV50');if old then old.stopped=true end
local S={version=53,stopped=false,elapsed=0,nextScan=0,candidates={},roots={},nativeRootPaths={}}
rawset(_G,'AC8HudPolicyV50',S)
local function call(o,k,...)
    if o~=api then return AC8Runtime.objectCall(o,k,...) end
    local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function full(o)return call(o,'get_full_name')end
local function xy(v)
    local x=field(v,'X') or field(v,'x');local y=field(v,'Y') or field(v,'y')
    if type(x)=='number' and type(y)=='number' and x==x and y==y and math.abs(x)<1e7 and math.abs(y)<1e7 then return {X=x,Y=y}end
end
local slate=call(call(api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary'),'get_class_default_object')
local function geometry(w)return call(w,'GetPaintSpaceGeometry') or call(w,'GetCachedGeometry')end
local function parent(w)
    local p=call(w,'GetParent');if p then return p end
    local outer=call(w,'get_outer');if (full(outer) or ''):match('^WidgetTree ')then return call(outer,'get_outer')end
end
local function chain(w)
    local result,seen={},{}
    for _=1,32 do
        local n=full(w);if not n or seen[n]then return nil end;seen[n]=true
        local vis=call(w,'GetVisibility');local opacity=call(w,'GetRenderOpacity')
        if type(vis)~='number' or vis==1 or vis==2 or type(opacity)~='number' or opacity<=0 then return nil end
        result[#result+1]=w
        if S.roots[n] then return result end
        local p=parent(w);if not p then return nil end
        local active=call(p,'GetActiveWidget');if active and full(active)~=n then return nil end
        w=p
    end
end
local function rawBounds(w,rootGeometry,rootSize,inset)
    local g=geometry(w);local size=xy(call(slate,'GetLocalSize',g));inset=inset or 0
    if not size or size.X<=2*inset or size.Y<=2*inset then return nil end
    local points={}
    for _,v in ipairs({{X=inset,Y=inset},{X=size.X-inset,Y=inset},{X=inset,Y=size.Y-inset},{X=size.X-inset,Y=size.Y-inset}})do
        local p=xy(call(slate,'AbsoluteToLocal',rootGeometry,call(slate,'LocalToAbsolute',g,v)));if not p then return nil end
        points[#points+1]=p
    end
    
    if math.abs(points[1].Y-points[2].Y)>0.5 or math.abs(points[1].X-points[3].X)>0.5 then return nil end
    return {math.min(points[1].X,points[2].X)/rootSize.X,math.min(points[1].Y,points[3].Y)/rootSize.Y,
        math.max(points[1].X,points[2].X)/rootSize.X,math.max(points[1].Y,points[3].Y)/rootSize.Y}
end
local function intersection(a,b)
    if not a or not b then return nil end
    local r={math.max(a[1],b[1]),math.max(a[2],b[2]),math.min(a[3],b[3]),math.min(a[4],b[4])}
    if r[1]>=r[3] or r[2]>=r[4]then return nil end;return r
end
local function bounds(w,g,size,inset,cachedAncestors)
    local ancestors=cachedAncestors or chain(w);if not ancestors then return nil end
    local r=intersection(rawBounds(w,g,size,inset),{0,0,1,1});if not r then return nil end

    for _,a in ipairs(ancestors)do
        local c=call(a,'GetClipping') or call(a,'get_property','Clipping')
        if c==1 or c==2 or c==3 or c==4 then
            local clip=rawBounds(a,g,size,0)
            if clip then r=intersection(r,clip);if not r then return nil end end
            if c==2 then break end
        end
    end
    return r
end
local function kind(n,w)
    local class,path=n:match('^(%S+) (.+)$');if not path then return nil end
    local leaf=path:match('%.([^%.]+)$') or ''
    -- radio follows the common authored glow. A special widget rectangle
    -- forced full brightness and introduced a hard response boundary.
    if class=='Image' and leaf=='Portrait' and path:find('.HUDMessageWidget.',1,true)then return 'portrait',2,{1,1,0,1}end

    if class=='Image' and leaf=='LayerTwoBackground' and path:find('.WBP_HUD_Message_000.',1,true)then return 'banner',0,{1,0,1,1}end

    if class=='Image' and leaf=='PlaneIconBackGround' and path:find('.WBP_PlayerStateWidget_1.',1,true)
        and (full(call(w,'GetParent')) or ''):match('%.PlaneCanvas$') then return 'plane-linework',0,{0,0,1,0}end
    if class=='ProgressBar' and path:find('.WBP_PlayerStateWidget_1.',1,true) then
        local p=full(call(w,'GetParent')) or ''
        if leaf:match('^MissilePB%d+$') and p:match('%.Weapons$') then return 'missile-art',0,{0,0,1,0}end
        if (leaf:match('^FlarePB%d+$') or leaf:match('^ChaffPB%d+$')) and
            (p:match('%.Flares$') or p:match('%.Chaffs$')) then return 'countermeasure-art',0,{0,0,1,0}end
    end

end

-- Direct hierarchy discovery helpers: walk only the target widget's branch
local function iterChildren(w)
    local children = {}
    if not w then return children end
    local okc, cc = pcall(function() return call(w, 'GetChildrenCount') or 0 end)
    if okc and type(cc) == 'number' and cc > 0 then
        for i = 0, cc - 1 do
            local ok2, c = pcall(function() return call(w, 'GetChildAt', i) end)
            if ok2 and c then children[#children + 1] = c end
        end
    end
    local wt = field(w, 'WidgetTree')
    if wt then
        local r = field(wt, 'RootWidget')
        if r then children[#children + 1] = r end
    end
    return children
end

local function findDesc(root, target, maxd, exact)
    if not root then return nil end
    local seen, found = {}, nil
    local function rec(w, d)
        if not w or found or d > maxd then return end
        local addr = tostring(w)
        if seen[addr] then return end
        seen[addr] = true
        local fn = full(w) or ''
        local nm = fn:match('%.([^%.]+)$') or fn:match('^%S+ (.+)$') or fn
        local hit = exact and (nm == target) or (not exact and nm:find(target, 1, true) ~= nil)
        if hit then found = w; return end
        for _, c in ipairs(iterChildren(w)) do rec(c, d + 1) end
    end
    rec(root, 0)
    return found
end

local function findDescAll(root, targetPattern, maxd)
    local results = {}
    if not root then return results end
    local seen = {}
    local function rec(w, d)
        if not w or d > maxd then return end
        local addr = tostring(w)
        if seen[addr] then return end
        seen[addr] = true
        local fn = full(w) or ''
        local nm = fn:match('%.([^%.]+)$') or fn:match('^%S+ (.+)$') or fn
        if nm:match(targetPattern) then
            results[#results + 1] = w
        end
        for _, c in ipairs(iterChildren(w)) do rec(c, d + 1) end
    end
    rec(root, 0)
    return results
end

-- Rebuild UI cache function: can be called anytime externally or on demand
local rebuildUIRectangles

local function rebuildUICache(force)
    if not force and S.candidates and #S.candidates > 0 and S.root and full(S.root) == S.rootName then
        return true
    end
    S.candidates={};S.roots={};S.root=nil
    local pc = call(api, 'get_player_controller', 0)
    local hud = pc and call(pc, 'GetHUD')
    if not hud then return false end
    local hudWidget = call(hud, 'get_property', 'HudWidget')
    local msgWidget = call(hud, 'get_property', 'HUDMessageWidget')
    S.root = hudWidget
    S.rootName = full(S.root)
    if not S.rootName then return false end

    -- [FAST PATH] Targeted direct hierarchy lookup: 0 UMG.Widget global scans
    local fastCandidates = {}
    local function addCandidate(w, category, inset, flags)
        if not w then return end
        local n = full(w)
        if not n then return end
        local ancestors = chain(w)
        if ancestors then
            fastCandidates[#fastCandidates + 1] = {
                widget = w,
                name = n,
                category = category,
                inset = inset,
                flags = flags,
                ancestors = ancestors
            }
        end
    end

    -- 1. Radio portrait & banner: direct under HUDMessageWidget
    if msgWidget then
        local portrait = findDesc(msgWidget, 'Portrait', 8, true)
        if portrait then addCandidate(portrait, 'portrait', 2, {1, 1, 0, 1}) end
        local banner = findDesc(msgWidget, 'LayerTwoBackground', 8, true)
        if banner then addCandidate(banner, 'banner', 0, {1, 0, 1, 1}) end
    end

    -- 2. Player state, weapons, flares, chaff: direct under HudWidget
    if hudWidget then
        local planeBg = findDesc(hudWidget, 'PlaneIconBackGround', 12, true)
        if planeBg then addCandidate(planeBg, 'plane-linework', 0, {0, 0, 1, 0}) end

        local missiles = findDescAll(hudWidget, '^MissilePB%d+$', 14)
        for _, m in ipairs(missiles) do addCandidate(m, 'missile-art', 0, {0, 0, 1, 0}) end

        local flares = findDescAll(hudWidget, '^FlarePB%d+$', 14)
        for _, f in ipairs(flares) do addCandidate(f, 'countermeasure-art', 0, {0, 0, 1, 0}) end

        local chaffs = findDescAll(hudWidget, '^ChaffPB%d+$', 14)
        for _, c in ipairs(chaffs) do addCandidate(c, 'countermeasure-art', 0, {0, 0, 1, 0}) end
    end

    if #fastCandidates > 0 then
        local priority = {portrait = 1, ['plane-linework'] = 2, ['missile-art'] = 3, ['countermeasure-art'] = 3, banner = 4, ['radio-normal-glow'] = 5}
        table.sort(fastCandidates, function(a, b)
            local pa, pb = priority[a.category] or 9, priority[b.category] or 9
            if pa ~= pb then return pa < pb end
            return a.name < b.name
        end)
        while #fastCandidates > 128 do table.remove(fastCandidates) end
        S.candidates = fastCandidates
        S.directHits = (S.directHits or 0) + 1
        if rebuildUIRectangles then rebuildUIRectangles(true) end
        return true
    end

    -- [FALLBACK PATH] Bounded scan only if direct tree lookup yielded nothing
    local roots = call(call(api, 'find_uobject', 'Class /Script/UMG.UserWidget'), 'get_objects_matching', false) or {}
    local prefixes, ownedRoots = {}, {}
    local function addRoot(w)
        local n = full(w) or ''; local path = n:match('^%S+ (.+)$')
        if path and path:find('/Engine/Transient.', 1, true) and not S.roots[n] then S.roots[n] = true; prefixes[#prefixes + 1] = path; ownedRoots[#ownedRoots + 1] = w end
    end

    for _, key in ipairs({'HudWidget', 'SubtitleWidget', 'HUDMessageWidget', 'NonGlowWidget', 'GlowWidgetPtr', 'NonGlowFrontWidgetPtr', 'NonGlowBackWidgetPtr'}) do
        addRoot(call(hud, 'get_property', key))
    end
    for _, w in ipairs(roots) do
        local n = full(w) or ''; local path = n:match('^%S+ (.+)$')
        if path and path:find('/Engine/Transient.', 1, true) and
            (call(w, 'IsInViewport') == true or (S.elapsed < (S.nativeRootsUntil or 0) and S.nativeRootPaths[path])) then
            addRoot(w)
        end
    end
    local widgets, seen = {}, {}
    local complete = true
    for _, root in ipairs(ownedRoots) do
        local owned = AC8Runtime.ownedWidgets(root)
        if not owned then complete = false; break end
        for _, w in ipairs(owned) do
            local n = full(w)
            if n and not seen[n] then seen[n] = true; widgets[#widgets + 1] = w end
        end
    end
    if not complete then
        widgets = call(call(api, 'find_uobject', 'Class /Script/UMG.Widget'), 'get_objects_matching', false) or {}
        S.fallbackScans = (S.fallbackScans or 0) + 1
    else S.ownedScans = (S.ownedScans or 0) + 1 end
    for i, w in ipairs(widgets) do
        if i > 32768 then break end
        local n = full(w) or ''; local category, inset, flags = kind(n, w); local path = n:match('^%S+ (.+)$')
        if category and path then
            for _, prefix in ipairs(prefixes) do
                if path == prefix or path:sub(1, #prefix + 1) == prefix .. '.' then
                    local ancestors = chain(w)
                    if ancestors then S.candidates[#S.candidates + 1] = {widget = w, name = n, category = category, inset = inset, flags = flags, ancestors = ancestors} end
                    break
                end
            end
        end
    end
    local priority = {portrait = 1, ['plane-linework'] = 2, ['missile-art'] = 3, ['countermeasure-art'] = 3, banner = 4, ['radio-normal-glow'] = 5}
    table.sort(S.candidates, function(a, b)
        local pa, pb = priority[a.category] or 9, priority[b.category] or 9
        if pa ~= pb then return pa < pb end; return a.name < b.name
    end)
    while #S.candidates > 128 do table.remove(S.candidates) end
    if #S.candidates > 0 and rebuildUIRectangles then
        rebuildUIRectangles(true)
    end
    return #S.candidates > 0
end
local discover = rebuildUICache

-- Compute and cache UI policy rectangles: eliminates per-frame Slate matrix transforms
rebuildUIRectangles = function(force)
    if not force and S.cachedRectangles and #S.cachedRectangles > 0 and S.root and full(S.root) == S.rootName then
        return S.cachedRectangles
    end
    if not S.root or full(S.root) ~= S.rootName or not S.candidates or #S.candidates == 0 then
        return S.cachedRectangles or {}
    end
    local g = geometry(S.root)
    local size = xy(call(slate, 'GetLocalSize', g))
    if not size or size.X <= 0 or size.Y <= 0 then
        return S.cachedRectangles or {}
    end

    local rectangles = {}
    local function add(r, flags, name, category)
        if not r then return end
        for i = #rectangles, 1, -1 do
            local a = rectangles[i]; local same = true
            for j = 1, 4 do if flags[j] ~= a.flags[j] then same = false end end
            if same then
                if r[1] >= a.bounds[1] and r[2] >= a.bounds[2] and r[3] <= a.bounds[3] and r[4] <= a.bounds[4] then return end
                if a.bounds[1] >= r[1] and a.bounds[2] >= r[2] and a.bounds[3] <= r[3] and a.bounds[4] <= r[4] then table.remove(rectangles, i) end
            end
        end
        rectangles[#rectangles + 1] = { bounds = r, flags = flags }
    end

    for _, c in ipairs(S.candidates) do
        if full(c.widget) == c.name then
            local usable = true
            if c.category == 'portrait' then
                local brush = call(c.widget, 'GetBrush') or call(c.widget, 'get_property', 'Brush')
                local resource = field(brush, 'ResourceObject')
                local color = call(c.widget, 'GetColorAndOpacity') or call(c.widget, 'get_property', 'ColorAndOpacity')
                local alpha = field(color, 'A')
                usable = resource ~= nil and (type(alpha) ~= 'number' or alpha > 0)
            end
            local r = usable and bounds(c.widget, g, size, c.inset, c.ancestors)
            if r then
                add(r, c.flags, c.name, c.category)
                if c.category == 'portrait' then
                    local outer = bounds(c.widget, g, size, 0, c.ancestors)
                    local inner = rawBounds(c.widget, g, size, c.inset)
                    if outer and inner then
                        local strips = {
                            { outer[1], outer[2], outer[3], inner[2] },
                            { outer[1], inner[4], outer[3], outer[4] },
                            { outer[1], inner[2], inner[1], inner[4] },
                            { inner[3], inner[2], outer[3], inner[4] }
                        }
                        for _, strip in ipairs(strips) do
                            add(intersection(strip, outer), { 0, 0, 3, 0 }, c.name, 'portrait-border')
                        end
                    end
                end
            end
        end
    end
    if #rectangles > 48 then rectangles = {}; S.overflow = true else S.overflow = false end
    S.cachedRectangles = rectangles
    S.lastRectCalc = S.elapsed
    return rectangles
end

-- Expose UI cache and rectangle rebuild functions globally and via AC8Runtime
rawset(_G, 'AC8_RefreshUICache', function(force)
    local ok = rebuildUICache(force == nil or force == true)
    if ok and rebuildUIRectangles then rebuildUIRectangles(true) end
    return ok
end)
rawset(_G, 'AC8_RefreshUIRectangles', function(force)
    return rebuildUIRectangles(force == nil or force == true)
end)
if type(AC8Runtime) == 'table' then
    AC8Runtime.refreshUICache = function(force)
        local ok = rebuildUICache(force == nil or force == true)
        if ok and rebuildUIRectangles then rebuildUIRectangles(true) end
        return ok
    end
    AC8Runtime.refreshUIRectangles = function(force)
        return rebuildUIRectangles(force == nil or force == true)
    end
end

-- Compare geometry every frame and reuse the serialized packet when unchanged.
-- Continue sending it every frame: the native 250ms stale-policy safeguard uses
-- wall time, so a paused/dilated game clock must never delay its heartbeat.
local function publishPolicy(rectangles)
    local changed=not S.policyValues or S.policyCount~=#rectangles
    if not changed then
        local index=1
        for _,r in ipairs(rectangles)do
            for i=1,4 do
                if S.policyValues[index+i-1]~=r.bounds[i] or S.policyValues[index+i+3]~=r.flags[i]then changed=true end
            end
            index=index+8
        end
    end
    if changed then
        local values={tostring(#rectangles)};S.policyValues={};S.policyCount=#rectangles
        for _,r in ipairs(rectangles)do
            for _,v in ipairs(r.bounds)do values[#values+1]=string.format('%.9g',v);S.policyValues[#S.policyValues+1]=v end
            for _,v in ipairs(r.flags)do values[#values+1]=tostring(v);S.policyValues[#S.policyValues+1]=v end
        end
        S.policyPacket=table.concat(values,'|');S.policyBuilds=(S.policyBuilds or 0)+1
    end
    local ok=pcall(function()api:dispatch_custom_event('AC8_HUD_PolicyV50',S.policyPacket)end)
    if ok then S.policySends=(S.policySends or 0)+1 end
end
local function update(delta)
    if S.stopped then return end
    S.elapsed=S.elapsed+math.max(0,math.min(tonumber(delta) or 0.016,1))
    
    -- Cache-driven update: only scan on epoch change or when cache is empty with bounded retry
    local currentEpoch = AC8Runtime and AC8Runtime.context and AC8Runtime.context.epoch or 0
    if S.lastEpoch ~= currentEpoch then
        S.lastEpoch = currentEpoch
        rebuildUICache(true)
        rebuildUIRectangles(true)
    elseif (not S.candidates or #S.candidates == 0) and (S.elapsed >= (S.nextRetry or 0)) then
        if rebuildUICache(false) then
            rebuildUIRectangles(true)
        else
            S.nextRetry = S.elapsed + 3.0
        end
    elseif not S.cachedRectangles or #S.cachedRectangles == 0 then
        rebuildUIRectangles(false)
    end

    -- Zero Slate geometry calculations on regular frames: send cached policy to C++ heartbeat
    publishPolicy(S.cachedRectangles or {})

end
uevr.sdk.callbacks.on_post_engine_tick(function(_,delta)update(delta)end)
uevr.sdk.callbacks.on_lua_event(function(name,data)
    if S.stopped or name~='AC8_UI_RegisteredRoots' or type(data)~='string'then return end
    S.nativeRootPaths={};S.nativeRootsUntil=S.elapsed+1.25;
    rebuildUICache(true)
    for path in data:gmatch('[^|]+')do S.nativeRootPaths[path]=true end
end)

end)(AC8Runtime.host('utility','ac8_hud_policy.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['tutorial_fill'], 'Duplicate AC8 VR section: tutorial_fill')
registry.sections['tutorial_fill'] = function(R)
do
-- ac8 tutorial fill
(function(uevr,json,print)

local live=AC8_TUTORIAL_FILL_LIVE==true
local existing=rawget(_G,'AC8_TutorialFill')
if live and existing and existing.persistent and existing.version>=7 and not existing.stopped then return end
if existing then assert(existing.stop(),'Previous tutorial fill originals could not be restored') end
local oneShot=rawget(_G,'AC8_TutorialFillTest')
if oneShot then assert(oneShot.restore(),'Old tutorial inset could not be restored');oneShot.finished=true end
local S={version=7,persistent=not live,stopped=false,ticks=0,records={},writes=0,failures=0,restores=0,scale=1,scaleX=1,scaleY=1,alpha=.85,inset=2}
rawset(_G,'AC8_TutorialFill',S)
local function call(o,k,...)
    if not o then return nil end
    local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function full(o)return call(o,'get_full_name')end
local function prop(o,k)return call(o,'get_property',k)end
local function margin(v)
    local ok,m=pcall(function()return {Left=v.Left,Top=v.Top,Right=v.Right,Bottom=v.Bottom}end)
    if not ok then return nil end
    for _,k in ipairs({'Left','Top','Right','Bottom'})do if type(m[k])~='number' or m[k]~=m[k] or math.abs(m[k])>20000 then return nil end end
    return m
end
local function equal(a,b)
    if not a or not b then return false end
    for _,k in ipairs({'Left','Top','Right','Bottom'})do if math.abs(a[k]-b[k])>.01 then return false end end
    return true
end
local function set(s,m)
    local ok=pcall(function()s:SetPadding(m)end)
    return ok and equal(margin(prop(s,'Padding')),m)
end
local function color(v)
    local ok,c=pcall(function()return {R=v.R,G=v.G,B=v.B,A=v.A}end)
    if not ok then return nil end
    for _,k in ipairs({'R','G','B','A'})do if type(c[k])~='number' or c[k]~=c[k] then return nil end end
    return c
end
local function style(o)
    local c=color(call(o,'GetColorAndOpacity') or prop(o,'ColorAndOpacity'))
    local v=call(o,'GetVisibility');local a=call(o,'GetRenderOpacity')
    if type(v)~='number' or type(a)~='number' then return nil end
    return {name=full(o),visibility=v,opacity=a,color=c}
end
local function appearance(o,v,a,c)
    local ok=pcall(function()
        if c then
            local prior=color(call(o,'GetColorAndOpacity') or prop(o,'ColorAndOpacity'))
            if not prior or math.abs(prior.R-c.R)>.001 or math.abs(prior.G-c.G)>.001 or math.abs(prior.B-c.B)>.001 or math.abs(prior.A-c.A)>.001 then o:SetColorAndOpacity(c) end
        end
        if math.abs((call(o,'GetRenderOpacity') or -1)-a)>.001 then o:SetRenderOpacity(a) end
        if call(o,'GetVisibility')~=v then o:SetVisibility(v) end
    end)
    local now=c and color(call(o,'GetColorAndOpacity') or prop(o,'ColorAndOpacity'))
    return ok and call(o,'GetVisibility')==v and math.abs((call(o,'GetRenderOpacity') or -1)-a)<.001
        and (not c or (now and math.abs(now.R-c.R)<.001 and math.abs(now.G-c.G)<.001 and math.abs(now.B-c.B)<.001 and math.abs(now.A-c.A)<.001))
end
local function restoreStyle(s)
    local o=call(uevr.api,'find_uobject',s.name)
    return not o or appearance(o,s.visibility,s.opacity,s.color)
end
local function redraw(name)
    local root=call(uevr.api,'find_uobject',name)
    if not root then return end
    call(root,'InvalidateLayoutAndVolatility')
    local parent=root
    for _=1,12 do
        if (full(parent) or ''):match('^RetainerBox ') then call(parent,'RequestRender') end
        parent=call(parent,'GetParent');if not parent then break end
    end
end
local function restore(name)
    local r=S.records[name];local s=call(uevr.api,'find_uobject',r.slot)
    local ok=not s or set(s,r.original)
    if r.imageSlot then
        local imageSlot=call(uevr.api,'find_uobject',r.imageSlot)
        ok=(not imageSlot or set(imageSlot,r.imagePadding)) and ok
        ok=restoreStyle(r.imageStyle) and ok
        ok=restoreStyle(r.blurStyle) and ok
    end
    if ok then redraw(name);S.records[name]=nil;S.restores=S.restores+1;return true end
    S.failures=S.failures+1;return false
end
local function restoreAll()
    local all,names=true,{}
    for n in pairs(S.records)do names[#names+1]=n end
    for _,n in ipairs(names)do if not restore(n) then all=false end end
    return all
end
function S.stop()local ok=restoreAll();if ok then S.stopped=true end;return ok end
local function active(w)
    if not call(w,'GetParent') then return false end
    local child=w
    for depth=1,12 do
        local v=call(child,'GetVisibility')
        if v==1 or v==2 or call(child,'GetRenderOpacity')==0 then return false end
        local p=call(child,'GetParent');if not p then return true end
        local selected=call(p,'GetActiveWidget')
        if selected and full(selected)~=full(child) then return false end
        child=p
    end
    return false
end
local function dimensions(v)
    local ok,x,y=pcall(function()return v.X,v.Y end)
    if ok and type(x)=='number' and type(y)=='number' and x>0 and y>0 and x<20000 and y<20000 then return {X=x,Y=y} end
end
local slate
local function paintedBounds(frame,parent)
    if not slate then
        local c=call(uevr.api,'find_uobject','Class /Script/UMG.SlateBlueprintLibrary')
        slate=call(c,'get_class_default_object')
    end
    local fg=call(frame,'GetCachedGeometry');local pg=call(parent,'GetCachedGeometry')
    local fs=dimensions(call(slate,'GetLocalSize',fg));local ps=dimensions(call(slate,'GetLocalSize',pg))
    if not fs or not ps then return nil end
    local first=call(slate,'LocalToAbsolute',fg,{X=0,Y=0})
    local last=call(slate,'LocalToAbsolute',fg,fs)
    local a=first and call(slate,'AbsoluteToLocal',pg,first)
    local b=last and call(slate,'AbsoluteToLocal',pg,last)
    local ok,x0,y0,x1,y1=pcall(function()return a.X,a.Y,b.X,b.Y end)
    if not ok or type(x0)~='number' or type(y0)~='number' or type(x1)~='number' or type(y1)~='number'
        or x0~=x0 or y0~=y0 or x1~=x1 or y1~=y1 or x0<0 or y0<0 or x1>ps.X+1 or y1>ps.Y+1
        or x1-x0<100 or y1-y0<100 then return nil end
    return {Left=x0+S.inset,Top=y0+S.inset,Right=ps.X-x1+S.inset,Bottom=ps.Y-y1+S.inset},ps
end
local statics
local function frameAppearance(frame)
    local v=call(frame,'GetVisibility');local a=call(frame,'GetRenderOpacity')
    if v==1 or v==2 then return 1,0 end
    return 4,type(a)=='number' and math.max(0,math.min(1,a)) or 1
end

pcall(function()uevr.sdk.callbacks.on_pre_engine_tick(function()
    if S.stopped or not next(S.records) then return end
    local pc=call(uevr.api,'get_player_controller',0)
    if not statics then statics=call(uevr.api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics')end
    if call(statics,'IsGamePaused',pc)~=true then restoreAll();return end
    for name,r in pairs(S.records)do
        local frame=call(uevr.api,'find_uobject',r.frame)
        local image=call(uevr.api,'find_uobject',r.imageStyle.name)
        if frame and image then
            local v,a=frameAppearance(frame)
            appearance(image,v,a*S.alpha,{R=0,G=0,B=0,A=1})
            if r.fillVisibility~=v or r.fillOpacity~=a then redraw(name);r.fillVisibility=v;r.fillOpacity=a end
        end
    end
end)end)

pcall(function()uevr.sdk.callbacks.on_pre_viewport_client_draw(function()
    if S.stopped then return end
    for name,r in pairs(S.records)do
        local frame=call(uevr.api,'find_uobject',r.frame)
        local image=call(uevr.api,'find_uobject',r.imageStyle.name)
        local blur=call(uevr.api,'find_uobject',r.blurStyle.name)
        if frame and image and blur then
            local v,a=frameAppearance(frame)
            local verified=appearance(image,v,a*S.alpha,{R=0,G=0,B=0,A=1}) and appearance(blur,1,r.blurStyle.opacity)
            r.lateVerified=verified
            if not verified then S.failures=S.failures+1 end
            if r.fillVisibility~=v or r.fillOpacity~=a then redraw(name);r.fillVisibility=v;r.fillOpacity=a end
        end
    end
end)end)

uevr.sdk.callbacks.on_post_engine_tick(function()
    if S.stopped then return end
    S.ticks=S.ticks+1
    local pc=call(uevr.api,'get_player_controller',0)
    if not statics then statics=call(uevr.api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics')end
    local paused=call(statics,'IsGamePaused',pc)
    local pauseEdge=S.paused~=paused;S.paused=paused
    local interval=paused==true and 1 or 30
    if not pauseEdge and S.ticks~=1 and S.ticks%interval~=0 then return end
    local hud=call(pc,'GetHUD');local hn=full(hud) or ''
    local controlsOk,controls=pcall(function()return json.load_file('ac8_tutorial_fill_controls.json')end)
    local scale=controlsOk and type(controls)=='table' and tonumber(controls.scale) or 1
    if not scale or scale~=scale then scale=1 end
    S.scale=math.max(.5,math.min(1,scale))
    local sx=controlsOk and type(controls)=='table' and tonumber(controls.scaleX) or S.scale
    local sy=controlsOk and type(controls)=='table' and tonumber(controls.scaleY) or S.scale
    if not sx or sx~=sx then sx=S.scale end;if not sy or sy~=sy then sy=S.scale end
    S.scaleX=math.max(.5,math.min(1,sx));S.scaleY=math.max(.5,math.min(1,sy))
    local alpha=controlsOk and type(controls)=='table' and tonumber(controls.alpha) or .85
    local inset=controlsOk and type(controls)=='table' and tonumber(controls.inset) or 2
    S.alpha=type(alpha)=='number' and alpha==alpha and math.max(0,math.min(1,alpha)) or .85
    S.inset=type(inset)=='number' and inset==inset and math.max(0,math.min(16,inset)) or 2
    if S.hud and S.hud~=hn then restoreAll();S.candidates=nil;S.mode='idle' end
    S.hud=hn
    if not hn:match('^LiveMainHUDParent4K_C ') or paused~=true then
        restoreAll();if S.mode~='idle' then ;S.mode='idle' end;return
    end
    local cls=call(uevr.api,'find_uobject','Class /Script/UMG.UserWidget')
    local widgets={}

    if S.candidates and S.mode=='tutorial' and not pauseEdge and S.ticks%30~=0 then
        for _,n in ipairs(S.candidates)do local w=call(uevr.api,'find_uobject',n);if w then widgets[#widgets+1]=w end end
    else
        widgets=call(cls,'get_objects_matching',false) or {};S.candidates={}
        for i,w in ipairs(widgets)do
            if i>4096 then break end
            local n=full(w) or ''
            if n:find('/Engine/Transient.',1,true) and (n:match('^WBP_Menu_Common_Dialog_000_C ') or n:match('^WBP_Menu_Common_Dialog_Parts_Contents_CP_002_C ')) then S.candidates[#S.candidates+1]=n end
        end
    end
    local roots,contents={},{ }
    for i,w in ipairs(widgets)do
        if i>4096 then break end
        local n=full(w) or ''
        if n:find('/Engine/Transient.',1,true) and not n:find('Default__',1,true) then
            if n:match('^WBP_Menu_Common_Dialog_000_C ') and call(w,'GetVisibility')==0 then roots[#roots+1]={object=w,name=n,path=n:match('^%S+ (.+)$')} end
            if n:match('^WBP_Menu_Common_Dialog_Parts_Contents_CP_002_C ') and active(w) then contents[#contents+1]={object=w,name=n} end
        end
    end
    local seen,rows={},{}
    for _,root in ipairs(roots)do
        local tutorial=false
        for _,c in ipairs(contents)do if c.name:find(root.path..'.',1,true) then tutorial=true;break end end
        if tutorial then
            local tree=prop(root.object,'WidgetTree');local treeName=full(tree)
            local blur=call(root.object,'get_property','MaskBackgroundBlur_Bg')
            local frame=prop(root.object,'GridPanel_Frame')
            local image=prop(root.object,'Image_Background')
            
            if treeName then
                local path=treeName:match('^%S+ (.+)$')
                blur=blur or call(uevr.api,'find_uobject','BackgroundBlurWithMask '..path..'.MaskBackgroundBlur_Bg')
                frame=frame or call(uevr.api,'find_uobject','GridPanel '..path..'.GridPanel_Frame')
                image=image or call(uevr.api,'find_uobject','Image '..path..'.Image_Background')
            end
            local parent=call(blur,'GetParent');local slot=prop(blur,'Slot');local sn=full(slot)
            local size=dimensions(call(frame,'GetDesiredSize'))
            local imageSlot=prop(image,'Slot');local imageSlotName=full(imageSlot)
            if blur and frame and image and full(parent)==full(call(frame,'GetParent'))
                and full(parent)==full(call(image,'GetParent')) and sn and imageSlotName and size then
                local r=S.records[root.name]
                if not r then
                    local canvas=dimensions(call(parent,'GetDesiredSize'));local original=margin(prop(slot,'Padding'))
                    local ip=margin(prop(imageSlot,'Padding'));local bs=style(blur);local ims=style(image)
                    if canvas and original and ip and bs and ims and ims.color and canvas.X>=size.X and canvas.Y>=size.Y then
                        r={slot=sn,original=original,canvas=canvas,imageSlot=imageSlotName,imagePadding=ip,blurStyle=bs,imageStyle=ims,frame=full(frame)};S.records[root.name]=r
                    end
                end
                if r and r.slot==sn and r.canvas.X>=size.X and r.canvas.Y>=size.Y then
                    seen[root.name]=true
                    local fill={X=size.X*S.scaleX,Y=size.Y*S.scaleY}
                    local x=(r.canvas.X-fill.X)*.5+S.inset;local y=(r.canvas.Y-fill.Y)*.5+S.inset
                    local wanted={Left=x,Right=x,Top=y,Bottom=y}
                    local measured,allocated=paintedBounds(frame,parent)
                    local method=measured and 'painted frame bounds' or 'desired-size calibrated fallback'
                    if measured then wanted=measured;fill={X=allocated.X-wanted.Left-wanted.Right,Y=allocated.Y-wanted.Top-wanted.Bottom} end
                    local verified=equal(margin(prop(imageSlot,'Padding')),wanted)
                    if not verified then verified=set(imageSlot,wanted);if verified then S.writes=S.writes+1 else S.failures=S.failures+1 end end
                    
                    local fillVisibility,fillOpacity=frameAppearance(frame)
                    if verified then verified=appearance(image,fillVisibility,fillOpacity*S.alpha,{R=0,G=0,B=0,A=1}) end
                    if verified then verified=appearance(blur,1,r.blurStyle.opacity) end
                    if verified and (r.fillVisibility~=fillVisibility or r.fillOpacity~=fillOpacity) then
                        redraw(root.name);r.fillVisibility=fillVisibility;r.fillOpacity=fillOpacity
                    end
                    if not verified then S.failures=S.failures+1;restore(root.name);seen[root.name]=nil end
                    rows[#rows+1]={root=root.name,slot=imageSlotName,canvas=allocated or r.canvas,frame=size,fill=fill,
                        wanted=wanted,alpha=S.alpha,opacity=fillOpacity,method=method,verified=verified}
                end
            end
        end
    end
    local names={};for n in pairs(S.records)do if not seen[n] then names[#names+1]=n end end
    for _,n in ipairs(names)do restore(n) end
    local mode=#rows>0 and 'tutorial' or 'waiting_tutorial'
    if S.mode~=mode or S.ticks%60==0 then  end;S.mode=mode
end)

end)(AC8Runtime.host('utility','ac8_tutorial_fill.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['pause_attachment'], 'Duplicate AC8 VR section: pause_attachment')
registry.sections['pause_attachment'] = function(R)
-- Flat2VR Modding Community and Discord: preserve the necessary menu
-- attachment from inherited community HUD layout, limited to the current HUD's outer root.
-- Nested Pause/RootMenu children keep their native hierarchy and input route.
do
local R=AC8Runtime
local host=R.host('utility','pause menu attachment')
local S={version=58,epoch=-1,attached=0,failures=0};R.pauseMenuAttachment=S
local lastPauseGuard=nil
local function call(o,k,...)if not o then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function full(o)return call(o,'get_full_name')or''end
local statics=call(uevr.api,'find_uobject','GameplayStatics /Script/Engine.Default__GameplayStatics')
host.sdk.callbacks.on_post_engine_tick(function()
 if R.tick%30==1 or lastPauseGuard==nil then
  local ok,settings=pcall(R.read,'ac8_pause_controls.json')
  local enabled=not(ok and type(settings)=='table'and settings.enabled==false)
  if enabled~=lastPauseGuard then host.api:dispatch_custom_event('AC8_PauseTickGuard',enabled and'on'or'off');lastPauseGuard=enabled end
 end
 local c=R.context;if not c.flight then S.epoch=-1;return end
 local paused=call(statics,'IsGamePaused',c.pc)==true
 local changed=S.epoch~=c.epoch or S.paused~=paused
 S.epoch=c.epoch;S.paused=paused
 if not changed and R.tick%30~=1 then return end
 local root=call(c.hud,'get_property','HudMenuWidget');local name=full(root)
 if not name:match('^WBP_MenuGlowWidget_C /Engine/Transient%.')and not name:match('^WBP_RootMenuWidget_C /Engine/Transient%.')then return end
 -- If the game has parented the container already, do not reparent it.
 local attached=call(root,'IsInViewport')
 if attached==false and not call(root,'GetParent')then
  call(root,'AddToViewport');attached=call(root,'IsInViewport')
  if attached==true then S.attached=S.attached+1 else S.failures=S.failures+1 end
 end
 S.root=name;S.inViewport=attached
end)
end
end

assert(not registry.sections['hit_destroyed_restore'], 'Duplicate AC8 VR section: hit_destroyed_restore')
registry.sections['hit_destroyed_restore'] = function(R)
-- Community Breakthrough: Restore invisible HIT / DESTROYED / SHOOT text indicators
-- Neutralises Additive RetainerBox material and retain rendering to enable standard Slate alpha pass-through
do
local host = R.host('utility', 'hit destroyed indicator restore')
local additive_retainers = {}
local next_discover_tick = 0
local seen_addresses = {}

local function short_name(obj)
    local fn = R.objectCall(obj, 'get_full_name') or ''
    return fn:match('([^.]+)$') or fn
end

local function walk_widgets(widget, depth)
    if not widget or depth <= 0 or not R.isLiveObject(widget) then return end
    local addr = R.objectCall(widget, 'get_address') or 0
    if addr ~= 0 then
        if seen_addresses[addr] then return end
        seen_addresses[addr] = true
    end

    local sName = short_name(widget)
    if sName:find('RetainerBox_Additive', 1, true) then
        additive_retainers[#additive_retainers + 1] = widget
    end

    local count = R.objectCall(widget, 'GetChildrenCount') or 0
    if type(count) == 'number' and count > 0 then
        for i = 0, count - 1 do
            local child = R.objectCall(widget, 'GetChildAt', i)
            if child then
                walk_widgets(child, depth - 1)
            end
        end
    end
end

local function discover_additive_retainers()
    additive_retainers = {}
    seen_addresses = {}
    local c = R.context
    if not c or not c.pc then return end

    -- Root 1: SubtitleWidget from PlayerController HUD
    local hud = c.hud
    if hud and R.isLiveObject(hud) then
        local subtitleWidget = R.objectCall(hud, 'get_field', 'SubtitleWidget') or R.objectCall(hud, 'get_property', 'SubtitleWidget')
        if subtitleWidget then
            walk_widgets(subtitleWidget, 24)
        end
    end

    -- Root 2: HUDMessageWidget from MainFlight HUD
    local keep = c.root or (R.hudLayoutRefs and R.hudLayoutRefs.root)
    if keep and R.isLiveObject(keep) then
        local count = R.objectCall(keep, 'GetChildrenCount') or 0
        if type(count) == 'number' and count > 0 then
            for i = 0, count - 1 do
                local child = R.objectCall(keep, 'GetChildAt', i)
                if child then
                    local sn = short_name(child)
                    if sn:find('HUDMessage', 1, true) or sn:find('Subtitle', 1, true) then
                        walk_widgets(child, 24)
                    else
                        walk_widgets(child, 8)
                    end
                end
            end
        end
    end
end

local function neutralise_additive_retainers()
    for i = #additive_retainers, 1, -1 do
        local w = additive_retainers[i]
        if w and R.isLiveObject(w) then
            pcall(function() w:SetEffectMaterial(nil) end)
            pcall(function() w.EffectMaterial = nil end)
            pcall(function() w:SetRetainRendering(false) end)
            pcall(function() w.bRetainRender = false end)
        else
            table.remove(additive_retainers, i)
        end
    end
end

host.sdk.callbacks.on_post_engine_tick(function()
    local tick = R.tick or 0
    -- 300フレーム周期 (~5.0秒) で動的ウィジェット探索
    if tick >= next_discover_tick then
        next_discover_tick = tick + 300
        discover_additive_retainers()
    end

    -- 2フレーム周期 (~33ms) で加算ブレンド無力化パルス
    if tick % 2 == 0 and #additive_retainers > 0 then
        neutralise_additive_retainers()
    end
end)
end
end

if registry.start then registry.start() end

