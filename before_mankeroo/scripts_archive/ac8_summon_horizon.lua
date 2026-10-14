-- ac8_summon_horizon.lua
-- ACE COMBAT 8 - 水平儀（ピッチラダー）& 機砲レティクル 強制召喚スクリプト（実験用）

local api = uevr.api
if api == nil then return end

local function safe_call(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
end

local log_file = nil
pcall(function() log_file = io.open("data/ac8_summon_log.txt", "w") end)
local function log(str)
    if log_file then
        pcall(function()
            log_file:write(str .. "\n")
            log_file:flush()
        end)
    end
end

log("==================================================================")
log("  ACE COMBAT 8 - 水平儀召喚スクリプト 起動")
log("  起動日時: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("==================================================================\n")

local TARGET_NAMES = {
    ["noglowdynamicdrawcanvas"] = true,
    ["dynamicdrawcanvas"] = true,
    ["pitchmeterpanel"] = true,
    ["pitchmetercenter"] = true,
    ["pitchbarleft"] = true,
    ["pitchbarright"] = true,
    ["gunreticlebar"] = true,
    ["gunreticlebackground"] = true,
    ["positivepanel"] = true,
    ["negativepanel"] = true,
    ["halfpositivepanel"] = true,
    ["halfnegativepanel"] = true,
    ["maincanvas"] = true,
    ["lowestprioritydynamicdrawcanvas"] = true,
}

local cached_widgets = {}

local function scan_and_cache()
    local widget_class = safe_call(function() return api:find_uobject("Class /Script/UMG.Widget") end, nil)
    if not widget_class then return 0 end

    local all_widgets = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
    cached_widgets = {}
    local count = 0

    for _, w in ipairs(all_widgets) do
        local fname = safe_call(function() return w:get_full_name() end, "")
        if fname:find("MainFlight", 1, true) or fname:find("HUD_Chronicle", 1, true) then
            local short_name = fname:match("([^.]+)$") or ""
            local lshort = short_name:lower()
            
            local hit = TARGET_NAMES[lshort]
            if not hit and lshort:find("pitchmeterwidget") then hit = true end
            if not hit and lshort:find("pitchmeter") then hit = true end
            if not hit and lshort:find("gunreticle") then hit = true end

            if hit then
                table.insert(cached_widgets, { obj = w, name = short_name })
                count = count + 1
            end
        end
    end

    log(string.format("キャッシュ完了: 水平儀/照準パーツ %d 個をロックオンしました", count))
    return count
end

local function enforce_visibility()
    local applied = 0
    for _, item in ipairs(cached_widgets) do
        local w = item.obj
        local cur_vis = safe_call(function() return w:call("GetVisibility") end, nil)
        if cur_vis == 1 or cur_vis == 2 then
            safe_call(function() w:call("SetVisibility", 4) end) -- SelfHitTestInvisible
            applied = applied + 1
        end
        safe_call(function()
            local op = w:call("GetRenderOpacity")
            if op and op < 0.1 then w:call("SetRenderOpacity", 1.0) end
        end)
    end
    return applied
end

local count = scan_and_cache()
log(string.format("初回適用: %d 個のパーツを強制点灯させました", enforce_visibility()))

local tick_counter = 0
local function on_tick()
    tick_counter = tick_counter + 1
    if tick_counter % 10 == 0 then enforce_visibility() end
    if tick_counter % 300 == 0 then scan_and_cache() end
end

pcall(function()
    uevr.sdk.callbacks.on_post_engine_tick(on_tick)
    log("常駐ループを開始しました")
end)
