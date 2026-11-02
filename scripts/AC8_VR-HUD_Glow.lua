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
local function dispatch(data)
    pcall(function() uevr.api:dispatch_custom_event('AC8_HUD_GlowLifecycle',data) end)
end
local function level(name)
    return name:match('^%S+ (.+%.PersistentLevel)%.') or name:match('^%S+ (.+)%.[^%.]+$')
end
local tutorialState=R.ensureTutorialState()
local function gameplayAllowed(c,name,paused)
    if not c.flight then return false end
    local vt=R.viewTargetName()
    if vt:find('CineCamera',1,true)or vt:find('CameraActor',1,true)or vt:find('PreviewObjectActor',1,true)then return false end
    if paused==true then return tutorialState.get(c.pc,name,true,R.tick).visible==true end
    if R.matchState()=='WaitingToStart'then return false end
    return true
end
local function update()
    local c=R.context
    local pc=c.pc
    local name=c.hudName or ''
    local paused=pc and R.paused() or nil
    local actualFlight=c.flight==true
    local hudLevel=level(name)
    local pausedMission=paused==true and lastFlight==true and
        (name=='' or (hudLevel~=nil and hudLevel==lastMissionLevel))
    local flight=(actualFlight or pausedMission)and not (AC8Runtime.missionLoading and AC8Runtime.missionLoading.active)
    local enabled=flight and gameplayAllowed(c,name,paused)
    R.glowGameplayAllowed=enabled
    if enabled~=lastFlight then dispatch(enabled and 'flight' or 'outside_flight');lastFlight=enabled end
    if actualFlight then
        local controller=R.objectCall(pc,'get_full_name')
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

end)(AC8Runtime.host('admission','ac8_glow_lifecycle.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['hud_policy'], 'Duplicate AC8 VR section: hud_policy')
registry.sections['hud_policy'] = function(R)
do
-- hud policy.
(function(uevr,json,print)

local api=uevr.api
local old=rawget(_G,'AC8HudPolicyV50');if old then old.stopped=true end
local S={version=59,stopped=false,elapsed=0,nextScan=0,candidates={},roots={},nativeRootPaths={}}
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

-- Structural ancestor chain for candidate registration
local function structuralChain(w)
    local result, seen = {}, {}
    for _ = 1, 32 do
        local n = full(w)
        if not n or seen[n] then return nil end
        seen[n] = true
        result[#result + 1] = w
        if S.roots[n] then return result end
        local p = parent(w)
        if not p then return nil end
        w = p
    end
    return nil
end

-- Live ancestor chain for runtime visibility & bounding evaluation
local function chain(w)
    local result, seen = {}, {}
    for _ = 1, 32 do
        local n = full(w)
        if not n or seen[n] then return nil end
        seen[n] = true
        local vis = call(w, 'GetVisibility')
        local opacity = call(w, 'GetRenderOpacity')
        if type(vis) ~= 'number' or vis == 1 or vis == 2 or type(opacity) ~= 'number' or opacity <= 0 then return nil end
        result[#result + 1] = w
        if S.roots[n] then return result end
        local p = parent(w)
        if not p then return nil end
        local active = call(p, 'GetActiveWidget')
        if active and full(active) ~= n then return nil end
        w = p
    end
    return nil
end

local function rawBounds(w,rootGeometry,rootSize,inset)
    local g=geometry(w);local size=xy(call(slate,'GetLocalSize',g));inset=inset or 0
    if not size or size.X<=2*inset or size.Y<=2*inset then return nil end
    local points={}
    for _,v in ipairs({{X=inset,Y=inset},{X=size.X-inset,Y=inset},{X=inset,Y=size.Y-inset},{X=size.X-inset,Y=size.Y-inset}})do
        local p=xy(call(slate,'AbsoluteToLocal',rootGeometry,call(slate,'LocalToAbsolute',g,v)));if not p then return nil end
        points[#points+1]=p
    end
    if math.abs(points[1].Y-points[2].Y)>2.5 or math.abs(points[1].X-points[3].X)>2.5 then return nil end
    return {
        math.min(points[1].X,points[2].X,points[3].X,points[4].X)/rootSize.X,
        math.min(points[1].Y,points[2].Y,points[3].Y,points[4].Y)/rootSize.Y,
        math.max(points[1].X,points[2].X,points[3].X,points[4].X)/rootSize.X,
        math.max(points[1].Y,points[2].Y,points[3].Y,points[4].Y)/rootSize.Y
    }
end

local function intersection(a,b)
    if not a or not b then return nil end
    local r={math.max(a[1],b[1]),math.max(a[2],b[2]),math.min(a[3],b[3]),math.min(a[4],b[4])}
    if r[1]>=r[3] or r[2]>=r[4]then return nil end;return r
end

local function bounds(w,g,size,inset)
    local ancestors = chain(w)
    if not ancestors then return nil end
    local r = intersection(rawBounds(w,g,size,inset),{0,0,1,1})
    if not r then return nil end

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
    local wt = call(w, 'get_property', 'WidgetTree') or field(w, 'WidgetTree')
    if wt then
        local r = call(wt, 'get_property', 'RootWidget') or field(wt, 'RootWidget')
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
    if not hudWidget then return false end
    S.root = hudWidget
    S.rootName = full(S.root)
    if not S.rootName then return false end

    local function addRoot(w)
        local n = full(w) or ''; local path = n:match('^%S+ (.+)$')
        if path and not S.roots[n] then S.roots[n] = true end
    end
    addRoot(hudWidget)

    local msgWidget = call(hudWidget, 'get_property', 'HUDMessageWidget')
        or call(hud, 'get_property', 'HUDMessageWidget')
        or findDesc(hudWidget, 'HUDMessageWidget', 8, true)
    if msgWidget then addRoot(msgWidget) end

    local subWidget = call(hud, 'get_property', 'SubtitleWidget')
        or call(hudWidget, 'get_property', 'SubtitleWidget')
        or findDesc(hudWidget, 'SubtitleWidget', 8, true)
    if subWidget then addRoot(subWidget) end

    for _, key in ipairs({'NonGlowWidget', 'GlowWidgetPtr', 'NonGlowFrontWidgetPtr', 'NonGlowBackWidgetPtr'}) do
        local w = call(hud, 'get_property', key)
        if w then addRoot(w) end
    end

    -- [FAST PATH] Targeted direct hierarchy lookup: 0 UMG.Widget global scans
    local fastCandidates = {}
    local seenWidgets = {}
    local function addCandidate(w, category, inset, flags)
        if not w then return end
        local n = full(w)
        if not n or seenWidgets[n] then return end
        -- Protect CutinSituation and LayerOne* (Mission Failed red glow)
        if n:find('CutinSituation', 1, true) or n:find('LayerOne', 1, true) then return end
        seenWidgets[n] = true
        if structuralChain(w) then
            fastCandidates[#fastCandidates + 1] = {
                widget = w,
                name = n,
                category = category,
                inset = inset,
                flags = flags
            }
        end
    end

    -- 1. Radio portrait, subtitles, combat messages & tutorial button guides: under msgRoots
    local msgRoots = {msgWidget, subWidget}
    for _, mr in ipairs(msgRoots) do
        if mr then
            local portrait = findDesc(mr, 'Portrait', 8, true)
            if portrait then addCandidate(portrait, 'portrait', 2, {1, 1, 0, 1}) end

            local radioBody = findDesc(mr, 'SubTitleMessageText', 12, true)
            if radioBody then addCandidate(radioBody, 'radio-text', 0, {1, 1, 0, 1}) end

            local banner = findDesc(mr, 'LayerTwoBackground', 10, true)
            if banner then addCandidate(banner, 'banner', 0, {1, 1, 0, 1}) end

            local layerTwoText = findDesc(mr, 'LayerTwoText', 10, true)
            if layerTwoText then addCandidate(layerTwoText, 'message-text', 0, {1, 1, 0, 1}) end

            local tutGuide0 = findDesc(mr, 'WBP_HUD_Tutorial_GuideText_000', 8, true)
            if tutGuide0 then
                local t0 = findDesc(tutGuide0, 'Text_Body', 6, true)
                if t0 then addCandidate(t0, 'tutorial-text', 0, {1, 1, 0, 1}) end
            end
            local tutGuide1 = findDesc(mr, 'WBP_HUD_Tutorial_GuideText_001', 8, true)
            if tutGuide1 then
                local t1 = findDesc(tutGuide1, 'Text_Body', 6, true)
                if t1 then addCandidate(t1, 'tutorial-text', 0, {1, 1, 0, 1}) end
            end
            local tutBtn = findDesc(mr, 'WBP_HUD_Tutorial_ButtonGuide_000', 8, true)
            if tutBtn then
                local btnIcons = findDescAll(tutBtn, '^WBP_HUD_Command_RealButton_Icon_', 8)
                for _, b in ipairs(btnIcons) do addCandidate(b, 'tutorial-icon', 0, {1, 1, 0, 1}) end
                local btnImages = findDescAll(tutBtn, '^Button_', 8)
                for _, b in ipairs(btnImages) do addCandidate(b, 'tutorial-icon', 0, {1, 1, 0, 1}) end
                local btnTexts = findDescAll(tutBtn, '^Text_', 8)
                for _, t in ipairs(btnTexts) do addCandidate(t, 'tutorial-text', 0, {1, 1, 0, 1}) end
            end

            local attention = findDesc(mr, 'WBP_HUD_Command_Attention', 8, true)
            if attention then
                local attIcon = findDesc(attention, 'WBP_HUD_Command_RealButton_Icon_000', 6, true)
                if attIcon then addCandidate(attIcon, 'command-icon', 0, {1, 1, 0, 1}) end
                local attText = findDesc(attention, 'Text_Body', 6, true)
                if attText then addCandidate(attText, 'command-text', 0, {1, 1, 0, 1}) end
            end

            for _, wname in ipairs({'WBP_HUD_Command_RealButton_000_Wingman', 'WBP_HUD_Command_RealButton_000_YesNo', 'WBP_HUD_Command_Wingman_000'}) do
                local wcmd = findDesc(mr, wname, 8, true)
                if wcmd then
                    local icons = findDescAll(wcmd, '^Button_', 8)
                    for _, icon in ipairs(icons) do addCandidate(icon, 'command-icon', 0, {1, 1, 0, 1}) end
                    local ricons = findDescAll(wcmd, '^WBP_HUD_Command_RealButton_Icon_', 8)
                    for _, icon in ipairs(ricons) do addCandidate(icon, 'command-icon', 0, {1, 1, 0, 1}) end
                    local texts = findDescAll(wcmd, '^Text_Body', 8)
                    for _, t in ipairs(texts) do addCandidate(t, 'command-text', 0, {1, 1, 0, 1}) end
                end
            end
        end
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
        local priority = {
            portrait = 1,
            ['plane-linework'] = 2,
            ['radio-text'] = 3,
            ['message-text'] = 3,
            ['command-icon'] = 3,
            ['command-text'] = 3,
            ['tutorial-icon'] = 3,
            ['tutorial-text'] = 3,
            ['missile-art'] = 4,
            ['countermeasure-art'] = 4,
            banner = 5,
            ['radio-normal-glow'] = 6
        }
        table.sort(fastCandidates, function(a, b)
            local pa, pb = priority[a.category] or 9, priority[b.category] or 9
            if pa ~= pb then return pa < pb end
            return a.name < b.name
        end)
        while #fastCandidates > 48 do table.remove(fastCandidates) end
        S.candidates = fastCandidates
        S.directHits = (S.directHits or 0) + 1
        if rebuildUIRectangles then rebuildUIRectangles(true) end
        return true
    end

    return false
end

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
        local x0 = math.max(0.0, math.min(1.0, tonumber(r[1]) or 0.0))
        local y0 = math.max(0.0, math.min(1.0, tonumber(r[2]) or 0.0))
        local x1 = math.max(0.0, math.min(1.0, tonumber(r[3]) or 0.0))
        local y1 = math.max(0.0, math.min(1.0, tonumber(r[4]) or 0.0))
        if x0 >= x1 or y0 >= y1 then return end
        r = { x0, y0, x1, y1 }
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
            local r = usable and bounds(c.widget, g, size, c.inset)
            if r then
                add(r, c.flags, c.name, c.category)
                if c.category == 'portrait' then
                    local outer = bounds(c.widget, g, size, 0)
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
    while #rectangles > 48 do table.remove(rectangles) end
    S.cachedRectangles = rectangles
    S.lastRectCalc = S.elapsed
    return rectangles
end

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
            for _,v in ipairs(r.bounds)do
                local cv = math.max(0.0, math.min(1.0, tonumber(v) or 0.0))
                values[#values+1]=string.format('%.9g',cv);S.policyValues[#S.policyValues+1]=cv
            end
            for _,v in ipairs(r.flags)do values[#values+1]=tostring(v);S.policyValues[#S.policyValues+1]=v end
        end
        S.policyPacket=table.concat(values,'|');S.policyBuilds=(S.policyBuilds or 0)+1
    end
    local ok=pcall(function()api:dispatch_custom_event('AC8_HUD_PolicyV50',S.policyPacket)end)
    if ok then S.policySends=(S.policySends or 0)+1 end
end

local function discoverGlowSources()
    local c=AC8Runtime.context;if not c.flight then return end
    local hud=c.hud;local root=c.root;local hn=c.hudName or''
    local prefix=hn:match('^LiveMainHUDParent%w*_C (.+%.PersistentLevel)%.');if not prefix then return end
    local values={};local seen={}
    local function add(o)
        if not o or seen[o]then return end;seen[o]=true
        local a=call(o,'get_address');if type(a)=='number'and a>0 then values[#values+1]=string.format('%.0f',a)end
    end
    local function addWidget(w)
        for _,o in ipairs(AC8Runtime.ownedWidgets(w)or{w})do add(o)end
    end
    add(hud);addWidget(root)
    for _,key in ipairs({'HUDMessageWidget','SubtitleWidget','NonGlowWidget','GlowWidgetPtr','NonGlowFrontWidgetPtr','NonGlowBackWidgetPtr'})do
        addWidget(call(hud,'get_property',key)or call(root,'get_property',key))
    end
    local discovered=rawget(_G,'AC8TargetDiscovery')
    for _,entry in ipairs((discovered and discovered.level==prefix and discovered.actors)or{})do
        local actor=entry.actor;add(actor)
        for _,key in ipairs({'ContainerBox','ClockTargetPinBillboardImage','AntiClockTargetPinBillboardImage','AllianceText','ObjectTypeText','ObjectCallsignText','DistanceText','GamerTagText','NextTargetText'})do
            add(call(actor,'get_property',key))
        end
    end
    if #values>0 then pcall(function()api:dispatch_custom_event('AC8_GlowDiscoverySources',table.concat(values,'|'))end)end
end

local function update(delta)
    if S.stopped then return end
    if AC8Runtime.glowGameplayAllowed==false then S.candidates={};S.roots={};return end
    S.elapsed=S.elapsed+math.max(0,math.min(tonumber(delta) or 0.016,1))

    local currentEpoch = AC8Runtime and AC8Runtime.context and AC8Runtime.context.epoch or 0
    if S.lastEpoch ~= currentEpoch then
        S.lastEpoch = currentEpoch
        S.burstUntil = S.elapsed + 5.0
        S.nextBurstScan = 0
        rebuildUICache(true)
    elseif S.burstUntil and S.elapsed < S.burstUntil then
        if S.elapsed >= (S.nextBurstScan or 0) then
            S.nextBurstScan = S.elapsed + 0.25
            rebuildUICache(false)
        end
    elseif (not S.candidates or #S.candidates == 0) and (S.elapsed >= (S.nextRetry or 0)) then
        if not rebuildUICache(false) then
            S.nextRetry = S.elapsed + 2.0
        end
    elseif S.elapsed >= (S.nextPeriodicScan or 0) then
        S.nextPeriodicScan = S.elapsed + 2.0
        rebuildUICache(false)
    end

    if S.candidates and #S.candidates > 0 and (S.elapsed >= (S.nextCandidateRefresh or 0)) then
        S.nextCandidateRefresh = S.elapsed + 3.0
        local allValid = true
        for _, c in ipairs(S.candidates) do
            if not full(c.widget) then allValid = false; break end
        end
        if not allValid then
            rebuildUICache(true)
        end
    end

    rebuildUIRectangles(true)
    publishPolicy(S.cachedRectangles or {})
end

uevr.sdk.callbacks.on_post_engine_tick(function(_,delta)update(delta)end)
uevr.sdk.callbacks.on_lua_event(function(name,data)
    if S.stopped then return end
    if name=='AC8_GlowDiscoveryRequest'then discoverGlowSources();return end
    if name~='AC8_UI_RegisteredRoots' or type(data)~='string'then return end
    S.nativeRootPaths={};S.nativeRootsUntil=S.elapsed+1.25
    rebuildUICache(true)
    for path in data:gmatch('[^|]+')do S.nativeRootPaths[path]=true end
end)

end)(AC8Runtime.host('utility','ac8_hud_policy.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['glow_brightness'], 'Duplicate AC8 VR section: glow_brightness')
registry.sections['glow_brightness'] = function(R)
-- Default HUD glow brightness.
do
local host=R.host('utility','HUD glow brightness')
local function send()host.api:dispatch_custom_event('AC8_GlowFixBrightness','1.6|1')end
send()
local sent=false
host.sdk.callbacks.on_pre_engine_tick(function()
 if not sent then sent=true;send()end
end)
end


end
assert(not registry.sections['tutorial_fill'], 'Duplicate AC8 VR section: tutorial_fill')
registry.sections['tutorial_fill'] = function(R)
local tutorialState=R.ensureTutorialState()
do
-- Native tutorial card: the game owns Img_Base, its bounds, tint and fades.
(function(uevr,json,print)
local existing=rawget(_G,'AC8_TutorialFill')
if existing then assert(existing.stop(),'Previous tutorial originals could not be restored')end
local S={version=11,stopped=false,ticks=0,records={}}
rawset(_G,'AC8_TutorialFill',S)
local function call(o,k,...)
 if not o or(o~=uevr.api and not R.isLiveObject(o))then return nil end
 local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end
end
local function full(o)return call(o,'get_full_name')end
local function prop(o,k)return call(o,'get_property',k)end
local function resolve(name,object)
 if object and full(object)==name then return object end
 local found=call(uevr.api,'find_uobject',name);if full(found)==name then return found end
end
local function redraw(r)
 local root=resolve(r.rootName,r.rootObject);if not root then return end
 call(root,'InvalidateLayoutAndVolatility')
 local p=root
 for _=1,12 do
  if(full(p)or''):match('^RetainerBox ')then call(p,'RequestRender')end
  p=call(p,'GetParent');if not p then break end
 end
end
local function restore(name)
 local r=S.records[name];if not r then return true end
 local blur=resolve(r.blurName,r.blurObject)
 if blur and call(blur,'GetVisibility')==1 and r.originalVisibility~=1 then
  call(blur,'SetVisibility',r.originalVisibility)
  if call(blur,'GetVisibility')~=r.originalVisibility then return false end
  redraw(r)
 end
 S.records[name]=nil;return true
end
local function restoreAll()
 local ok,names=true,{};for n in pairs(S.records)do names[#names+1]=n end
 for _,n in ipairs(names)do if not restore(n)then ok=false end end;return ok
end
function S.stop()local ok=restoreAll();if ok then S.stopped=true end;return ok end
local function hide(r)
 local blur=resolve(r.blurName,r.blurObject);if not blur then return false end
 if call(blur,'GetVisibility')~=1 then
  call(blur,'SetVisibility',1)
  if call(blur,'GetVisibility')~=1 then return false end
  redraw(r)
 end
 return true
end
local function paused()
 return R.paused()
end
local function late()
 if S.stopped then return end
 for _,r in pairs(S.records)do hide(r)end
end
pcall(function()uevr.sdk.callbacks.on_pre_engine_tick(function()
 if S.stopped or not next(S.records)then return end
 if paused()~=true then restoreAll();return end
 late()
end)end)
pcall(function()uevr.sdk.callbacks.on_pre_viewport_client_draw(late)end)

uevr.sdk.callbacks.on_post_engine_tick(function()
 if S.stopped then return end
 S.ticks=S.ticks+1
 local pc=R.context.pc;local isPaused=paused()
 if isPaused~=true then tutorialState.get(pc,'',isPaused,S.ticks)end
 local edge=S.paused~=isPaused;S.paused=isPaused
 local hn=R.context.hudName or''
 if S.hud and S.hud~=hn then restoreAll()end;S.hud=hn
 if not hn:match('^LiveMainHUDParent%w*_C ')or isPaused~=true then
  restoreAll();return
 end
 if not edge and next(S.records)~=nil and S.ticks%30~=0 then return end
 local view=tutorialState.get(pc,hn,isPaused,S.ticks);local seen={}
 for _,root in ipairs(view.roots or{})do
  local tutorial=false
  for _,c in ipairs(view.contents or{})do if c.name:find(root.path..'.',1,true)then tutorial=true;break end end
  if tutorial then
   local tree=prop(root.object,'WidgetTree');local tn=full(tree);local path=tn and tn:match('^%S+ (.+)$')
   local function binding(key,cls)return prop(root.object,key)or(path and call(uevr.api,'find_uobject',cls..' '..path..'.'..key))end
   local blur=binding('MaskBackgroundBlur_Bg','BackgroundBlurWithMask')
   local base=binding('Img_Base','LiveNUIImage');local frame=binding('GridPanel_Frame','GridPanel')
   local bn,baseName,fn=full(blur),full(base),full(frame)
   if bn and baseName and fn and full(call(base,'GetParent'))==fn then
    local r=S.records[root.name]
    if r and r.blurName~=bn then restore(root.name);r=nil end
    if not r then
     local visibility=call(blur,'GetVisibility')
     if type(visibility)=='number'then r={rootName=root.name,rootObject=root.object,blurName=bn,blurObject=blur,originalVisibility=visibility};S.records[root.name]=r end
    end
    if r then
     seen[root.name]=true;hide(r)
    end
   end
  end
 end
 local names={};for n in pairs(S.records)do if not seen[n]then names[#names+1]=n end end
 for _,n in ipairs(names)do restore(n)end
end)
pcall(function()uevr.sdk.callbacks.on_script_reset(S.stop)end)

end)(AC8Runtime.host('utility','AC8_VR-TutorialFill.lua'),AC8Runtime.json,AC8Runtime.log)
end


end
assert(not registry.sections['pause_attachment'], 'Duplicate AC8 VR section: pause_attachment')
registry.sections['pause_attachment'] = function(R)
do
local R=AC8Runtime
local host=R.host('utility','pause menu attachment')
local S={version=58,epoch=-1,attached=0,failures=0};R.pauseMenuAttachment=S
local lastPauseGuard=nil
local function call(o,k,...)if not o then return end;local ok,v=pcall(function(...)return o[k](o,...)end,...);if ok then return v end end
local function full(o)return call(o,'get_full_name')or''end
host.sdk.callbacks.on_post_engine_tick(function()
 if R.tick%30==1 or lastPauseGuard==nil then
  local settings=R.read('AC8_VR-PauseControls.json')or R.read('ac8_pause_controls.json')
  local enabled=not(type(settings)=='table'and settings.enabled==false)
  if enabled~=lastPauseGuard then host.api:dispatch_custom_event('AC8_PauseTickGuard',enabled and'on'or'off');lastPauseGuard=enabled end
 end
 local c=R.context;if not c.flight then S.epoch=-1;return end
 local paused=R.paused()==true
 local changed=S.epoch~=c.epoch or S.paused~=paused
 S.epoch=c.epoch;S.paused=paused
 if not changed and R.tick%30~=1 then return end
 local root=call(c.hud,'get_property','HudMenuWidget');local name=full(root)
 if not name:match('^WBP_MenuGlowWidget_C /Engine/Transient%.')and not name:match('^WBP_RootMenuWidget_C /Engine/Transient%.')then return end
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
    if not c or not c.pc or not c.flight then return end

    local hud = c.hud
    if hud and R.isLiveObject(hud) then
        local subtitleWidget = R.objectCall(hud, 'get_field', 'SubtitleWidget') or R.objectCall(hud, 'get_property', 'SubtitleWidget')
        if subtitleWidget then
            walk_widgets(subtitleWidget, 24)
        end
    end

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
    if not R.context.flight then return end
    local tick = R.tick or 0
    if tick >= next_discover_tick then
        next_discover_tick = tick + 300
        discover_additive_retainers()
    end

    if tick % 2 == 0 and #additive_retainers > 0 then
        neutralise_additive_retainers()
    end
end)
end
end

if registry.start then registry.start() end
