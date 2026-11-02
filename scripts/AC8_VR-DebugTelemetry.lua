-- AC8_VR-DebugTelemetry.lua
-- Dedicated diagnostic & telemetry dump module for Ace Combat 8 VR.
-- Dumps canvas geometry, safe-frame math, widget hierarchy/positions, Glow policy rectangles,
-- and FPS / frame-time metrics to ac8_debug_telemetry.json (saved in data/ by UEVR json.dump_file).

local uevr = uevr
if not uevr then return end

local api = uevr.api
local vr = uevr.params and uevr.params.vr

local TELEMETRY_FILE = "ac8_debug_telemetry.json"

local get_async_keystate = nil
pcall(function()
    local ffi = require("ffi")
    ffi.cdef[[
        short GetAsyncKeyState(int vKey);
    ]]
    get_async_keystate = function(vkey)
        local ok, val = pcall(function() return ffi.C.GetAsyncKeyState(vkey) end)
        if ok and val and type(val) == "number" then
            return bit.band(val, 0x8000) ~= 0
        end
        return false
    end
end)

local M = {
    frameCount = 0,
    accumDt = 0.0,
    avgFps = 0.0,
    avgFrameMs = 0.0,
    minFps = 999.0,
    maxFrameMs = 0.0,
    autoDumpedForHudAddr = nil,
    flightWarmupFrames = 0,
    lastDumpStatus = "Not dumped yet",
    lastDumpFrame = 0,
    spaceWasDown = false,
    moduleTimingsMs = {},
    lastPolicyPacket = "",
    lastPolicyRectCount = 0,
    lastPolicyClampedCount = 0,
}

local function getRuntime()
    return rawget(_G, "AC8Runtime") or rawget(_G, "__AC8_VR_RUNTIME__") or {}
end

local function getJson()
    local R = getRuntime()
    return (R and R.realJSON) or (R and R.json) or rawget(_G, "json")
end

local function toJsonString(val)
    local t = type(val)
    if t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local isArray = (#val > 0)
        local parts = {}
        if isArray then
            for _, v in ipairs(val) do
                parts[#parts+1] = toJsonString(v)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                parts[#parts+1] = string.format("%q:%s", tostring(k), toJsonString(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

local function safeLive(obj)
    if not obj then return false end
    local R = getRuntime()
    if R.isLiveObject then
        local ok, res = pcall(R.isLiveObject, obj)
        return ok and res or false
    end
    local ok, name = pcall(function() return obj:get_full_name() end)
    return ok and type(name) == "string" and #name > 0
end

local function detectVrRuntime()
    local R = getRuntime()
    local isOpenXR = false
    local isOpenVR = false
    if vr then
        pcall(function()
            if vr.is_openxr then isOpenXR = vr:is_openxr() and true or false end
            if vr.is_openvr then isOpenVR = vr:is_openvr() and true or false end
        end)
    end
    local configuredMode = (R.RuntimeAdapter and R.RuntimeAdapter.mode) or (R.customHUDConfig and R.customHUDConfig.vrRuntimeMode) or "Auto"
    local resolvedMode = (R.RuntimeAdapter and R.RuntimeAdapter:resolve()) or (isOpenXR and "OpenXR" or (isOpenVR and "OpenVR" or "OpenXR"))
    return {
        is_openxr = isOpenXR,
        is_openvr = isOpenVR,
        configured_mode = configuredMode,
        resolved_mode = resolvedMode,
    }
end

local function inspectWidgetGeometry(w, sbl, rootGeom)
    if not safeLive(w) then
        return { alive = false }
    end
    local info = { alive = true }
    pcall(function() info.full_name = w:get_full_name() end)
    pcall(function() info.visibility = tostring(w:GetVisibility()) end)
    pcall(function() info.render_opacity = tonumber(w:GetRenderOpacity()) or 1.0 end)
    pcall(function()
        local rt = w:get_property("RenderTransform")
        if rt then
            if rt.Translation then
                info.render_translation = { x = rt.Translation.X or 0, y = rt.Translation.Y or 0 }
            end
            if rt.Scale then
                info.render_scale = { x = rt.Scale.X or 1, y = rt.Scale.Y or 1 }
            end
        end
    end)
    pcall(function()
        local slot = w:get_property("Slot")
        if safeLive(slot) then
            local pos = slot.GetPosition and slot:GetPosition()
            local sz = slot.GetSize and slot:GetSize()
            local align = slot.GetAlignment and slot:GetAlignment()
            local anchors = slot.GetAnchors and slot:GetAnchors()
            if pos then info.slot_pos = { x = pos.X or 0, y = pos.Y or 0 } end
            if sz then info.slot_size = { x = sz.X or 0, y = sz.Y or 0 } end
            if align then info.slot_align = { x = align.X or 0, y = align.Y or 0 } end
            if anchors and anchors.Minimum and anchors.Maximum then
                info.anchors = {
                    min_x = anchors.Minimum.X or 0,
                    min_y = anchors.Minimum.Y or 0,
                    max_x = anchors.Maximum.X or 0,
                    max_y = anchors.Maximum.Y or 0,
                }
            end
        end
    end)
    if sbl and rootGeom then
        pcall(function()
            local g = w:GetPaintSpaceGeometry() or w:GetCachedGeometry()
            if g then
                local lsz = sbl:GetLocalSize(g)
                if lsz then info.local_size = { x = lsz.X or 0, y = lsz.Y or 0 } end
                local zero = { X = 0.0, Y = 0.0 }
                local absPos = sbl:LocalToAbsolute(g, zero)
                if absPos then
                    info.abs_pos = { x = absPos.X or 0, y = absPos.Y or 0 }
                    local rootLocal = sbl:AbsoluteToLocal(rootGeom, absPos)
                    if rootLocal then
                        info.root_local_pos = { x = rootLocal.X or 0, y = rootLocal.Y or 0 }
                    end
                end
            end
        end)
    end
    return info
end

function M.dumpNow(reason)
    local ok, err = pcall(function()
        local R = getRuntime()
        R.DebugTelemetry = M
        local ctx = R.context or {}
        local refs = R.hudLayoutRefs or {}
        local hud = ctx.root or refs.root
        local sbl = nil
        if api then
            local cls = api:find_uobject("Class /Script/UMG.SlateBlueprintLibrary")
            if cls then sbl = cls:get_class_default_object() end
        end

        local rootGeom = nil
        local canvasSize = { x = 0, y = 0 }
        local safeFrame = {
            center_x = 0,
            center_y = 0,
            aspect_ratio = 0,
            margin_x = 0,
            margin_y = 0,
            safe_w = 0,
            safe_h = 0,
        }

        if safeLive(hud) and sbl then
            pcall(function()
                rootGeom = hud:GetPaintSpaceGeometry() or hud:GetCachedGeometry()
                if rootGeom then
                    local sz = sbl:GetLocalSize(rootGeom)
                    if sz and sz.X and sz.Y and sz.Y > 0 then
                        canvasSize.x = sz.X
                        canvasSize.y = sz.Y
                        safeFrame.center_x = sz.X * 0.5
                        safeFrame.center_y = sz.Y * 0.5
                        safeFrame.aspect_ratio = sz.X / sz.Y
                        local targetW = sz.Y * (16.0 / 9.0)
                        local targetH = sz.X * (9.0 / 16.0)
                        safeFrame.margin_x = math.max(0.0, (sz.X - targetW) * 0.5)
                        safeFrame.margin_y = math.max(0.0, (sz.Y - targetH) * 0.5)
                        safeFrame.safe_w = sz.X - 2.0 * safeFrame.margin_x
                        safeFrame.safe_h = sz.Y - 2.0 * safeFrame.margin_y
                    end
                end
            end)
        end

        if (not canvasSize.x or canvasSize.x == 0) and R.cachedCanvasVirtualSize then
            local cs = R.cachedCanvasVirtualSize
            if cs.X and cs.Y and cs.Y > 0 then
                canvasSize.x = cs.X
                canvasSize.y = cs.Y
                safeFrame.center_x = cs.X * 0.5
                safeFrame.center_y = cs.Y * 0.5
                safeFrame.aspect_ratio = cs.X / cs.Y
                local targetW = cs.Y * (16.0 / 9.0)
                local targetH = cs.X * (9.0 / 16.0)
                safeFrame.margin_x = math.max(0.0, (cs.X - targetW) * 0.5)
                safeFrame.margin_y = math.max(0.0, (cs.Y - targetH) * 0.5)
                safeFrame.safe_w = cs.X - 2.0 * safeFrame.margin_x
                safeFrame.safe_h = cs.Y - 2.0 * safeFrame.margin_y
            end
        end

        local widgets = {}
        if safeLive(hud) then
            widgets.MainFlightRoot = inspectWidgetGeometry(hud, sbl, rootGeom)
            local refMap = {
                Altimeter = refs.altimeter,
                WhiskyMarkPanel = refs.whisky,
                VelocityVector = refs.vel,
                VelocityIcon = refs.vicon,
                RadarRoot = refs.radar,
                AircraftInfo = refs.info,
                CampaignInfo = refs.campaign or refs.score,
                Locator = refs.locator,
                Wingman = refs.wingman,
                MainCanvas = refs.maincv,
            }
            if not safeLive(refMap.Locator) then
                local foundLoc = findDescendantByName(hud, "WBP_LocatorWidget")
                if not foundLoc and R.context and R.context.hud then
                    pcall(function()
                        local dyn = R.context.hud:get_property("DynamicCanvas")
                        if dyn then
                            for i = 0, math.min(dyn:GetChildrenCount() or 0, 64) - 1 do
                                local ch = dyn:GetChildAt(i)
                                local chn = ch and ch:get_full_name() or ""
                                if chn:match("%.WBP_LocatorWidget$") then
                                    foundLoc = ch
                                    break
                                end
                            end
                        end
                    end)
                end
                refMap.Locator = foundLoc
            end
            for k, w in pairs(refMap) do
                if safeLive(w) then
                    local info = inspectWidgetGeometry(w, sbl, rootGeom)
                    if k == "Locator" then
                        pcall(function()
                            local flo = w:get_property("FowardLocatorOffset")
                            if flo then info.foward_locator_offset = { x = flo.X, y = flo.Y } end
                        end)
                    end
                    widgets[k] = info
                end
            end
        end

        local pol = rawget(_G, "AC8HudPolicyV50")
        local rectCount = (pol and pol.policyCount) or M.lastPolicyRectCount or 0
        local packetStr = (pol and pol.policyPacket) or M.lastPolicyPacket or ""

        local payload = {
            mod_version = R.modVersion or "0.1.0.57",
            core_version = R.version or 105,
            dump_reason = reason or "manual",
            dump_frame = M.frameCount,
            vr_runtime = detectVrRuntime(),
            performance = {
                avg_fps = tonumber(string.format("%.2f", M.avgFps)),
                avg_frame_ms = tonumber(string.format("%.2f", M.avgFrameMs)),
                min_fps = tonumber(string.format("%.2f", M.minFps < 900 and M.minFps or 0)),
                max_frame_ms = tonumber(string.format("%.2f", M.maxFrameMs)),
                module_timings_ms = M.moduleTimingsMs,
            },
            canvas_geometry = {
                local_size = canvasSize,
                safe_frame_16_9 = safeFrame,
            },
            glow_policy = {
                last_rect_count = rectCount,
                last_clamped_count = M.lastPolicyClampedCount,
                last_packet = packetStr,
            },
            widgets = widgets,
            custom_hud_config = R.customHUDConfig or {},
            runtime_errors = R.errors or {},
        }

        local j = getJson()
        if j and j.dump_file then
            -- 1. Full snapshot overwrite (latest state in data/ac8_debug_telemetry.json)
            pcall(function() j.dump_file(TELEMETRY_FILE, payload, 2) end)
            -- 2. Append compact record to JSON Lines history (data/ac8_debug_telemetry.jsonl)
            pcall(function()
                local f = io.open("data/ac8_debug_telemetry.jsonl", "a")
                if f then
                    local lineRecord = {
                        timestamp = os.time(),
                        date = os.date("%Y-%m-%d %H:%M:%S"),
                        dump_reason = reason or "manual",
                        dump_frame = M.frameCount,
                        fps = payload.performance.avg_fps,
                        canvas_geometry = payload.canvas_geometry,
                        glow_policy = payload.glow_policy,
                        widgets = payload.widgets
                    }
                    local lineStr = (j.dump_string and j.dump_string(lineRecord)) or toJsonString(lineRecord)
                    lineStr = lineStr:gsub("[\r\n]+", " ")
                    f:write(lineStr .. "\n")
                    f:close()
                end
            end)
            M.lastDumpStatus = string.format("OK (%s @ frame %d)", tostring(reason), M.frameCount)
            M.lastDumpFrame = M.frameCount
        else
            M.lastDumpStatus = "json.dump_file unavailable"
        end
    end)
    if not ok then
        M.lastDumpStatus = "Error: " .. tostring(err)
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    local dt = tonumber(delta) or 0.0
    M.frameCount = M.frameCount + 1
    if dt > 0.0001 and dt < 1.0 then
        local instFps = 1.0 / dt
        local instMs = dt * 1000.0
        if M.avgFps <= 0.0 then
            M.avgFps = instFps
            M.avgFrameMs = instMs
        else
            M.avgFps = M.avgFps * 0.95 + instFps * 0.05
            M.avgFrameMs = M.avgFrameMs * 0.95 + instMs * 0.05
        end
        if M.frameCount > 120 then
            if instFps < M.minFps then M.minFps = instFps end
            if instMs > M.maxFrameMs then M.maxFrameMs = instMs end
        end
    end

    -- Hotkey: Space bar instant telemetry dump (debounced)
    if get_async_keystate then
        local spaceDown = get_async_keystate(0x20) -- VK_SPACE
        if spaceDown and not M.spaceWasDown then
            M.dumpNow("hotkey_space")
            print(string.format("[AC8-VR] Telemetry dumped via Space bar! Frame=%d", M.frameCount))
        end
        M.spaceWasDown = spaceDown
    end

    local R = getRuntime()
    R.DebugTelemetry = M
    local ctx = R.context
    local root = (R.hudLayoutRefs and R.hudLayoutRefs.root) or (ctx and ctx.root)
    if ctx and ctx.flight and safeLive(root) then
        local addr = nil
        pcall(function() addr = root:get_address() end)
        if addr and addr ~= M.autoDumpedForHudAddr then
            M.flightWarmupFrames = M.flightWarmupFrames + 1
            if M.flightWarmupFrames >= 60 then
                M.autoDumpedForHudAddr = addr
                M.flightWarmupFrames = 0
                M.dumpNow("auto_flight_entry")
            end
        end
    else
        M.flightWarmupFrames = 0
    end

    local isPaused = (ctx and ctx.flight and R.paused and R.paused() == true)
    if isPaused and not M.pausedDumped then
        M.pausedDumped = true
        M.dumpNow("pause_menu_opened")
    elseif not isPaused then
        M.pausedDumped = false
    end
end)

pcall(function()
    if uevr.lua and uevr.lua.add_script_panel then
        uevr.lua.add_script_panel("AC8 Debug Telemetry", function()
            if not imgui then return end
            imgui.text(string.format("FPS: %.1f (%.2f ms) | Min FPS: %.1f", M.avgFps, M.avgFrameMs, M.minFps < 900 and M.minFps or 0))
            imgui.text("Last Dump: " .. tostring(M.lastDumpStatus))
            if imgui.button("Dump Debug Telemetry Now") then
                M.dumpNow("manual_ui_button")
            end
            if imgui.button("Reset Min/Max FPS Stats") then
                M.minFps = 999.0
                M.maxFrameMs = 0.0
            end
        end)
    end
end)
