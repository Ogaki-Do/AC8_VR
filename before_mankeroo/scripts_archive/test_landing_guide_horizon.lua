-- test_landing_guide_horizon.lua (v2)
-- テンプレート（CDO）ではなく、実際の実行時インスタンス（Transient）を確実に捕まえて駆動する

local api = uevr.api
if api == nil then return end

local log_file = "data/landing_guide_log.txt"
local function log_txt(str)
    local f = io.open(log_file, "a")
    if f then
        f:write(os.date("%H:%M:%S ") .. tostring(str) .. "\n")
        f:close()
    end
end

pcall(function()
    local f = io.open(log_file, "w")
    if f then f:write("=== LandingGuide Horizon Test (v2) Started ===\n"); f:close() end
end)

local target_guide_parent = nil
local target_horizontal_bar = nil
local target_vertical_bar = nil
local cached = false
local tick_logged = false

-- 対象パーツの検索（Transientインスタンスのみ）
local function find_landing_guide()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return end

    local all_w = widget_class:get_objects_matching(false) or {}
    for _, w in ipairs(all_w) do
        local fname = w:get_full_name()
        -- Transient かつ Default__ を除外（実際の画面インスタンスのみ）
        if fname:find("Transient", 1, true) and not fname:find("Default__", 1, true) and fname:find("MainFlight", 1, true) then
            local sname = fname:match("([^.]+)$") or ""
            
            if sname == "LandingGuide" then
                target_guide_parent = w
                log_txt("★ Transient LandingGuide 捕捉: " .. fname)
            elseif sname == "LandingGuideHorizontal" then
                target_horizontal_bar = w
                log_txt("★ Transient LandingGuideHorizontal 捕捉: " .. fname)
            elseif sname == "LandingGuideVertical" then
                target_vertical_bar = w
                log_txt("★ Transient LandingGuideVertical 捕捉: " .. fname)
            end
        end
    end
    cached = true
end

-- 姿勢角の取得
local function get_attitude()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    if not pawn then return nil end

    local rot = pawn:call("K2_GetActorRotation")
    if not rot and pawn.RootComponent then
        rot = pawn.RootComponent.RelativeRotation
    end
    if rot then
        return {
            pitch = rot.Pitch or rot.pitch or 0.0,
            roll = rot.Roll or rot.roll or 0.0,
            yaw = rot.Yaw or rot.yaw or 0.0
        }
    end
    return nil
end

-- 毎フレームのリアルタイム駆動
uevr.sdk.callbacks.on_post_engine_tick(function()
    if not cached then
        find_landing_guide()
    end

    -- 1. 親パネル（LandingGuide）を表示化
    if target_guide_parent then
        local ok, err = pcall(function()
            target_guide_parent:call("SetVisibility", 0) -- Visible
            target_guide_parent:call("SetRenderOpacity", 1.0)
        end)
        if not ok and not tick_logged then
            log_txt("Error in guide_parent: " .. tostring(err))
        end
    end

    -- 2. 垂直バーは非表示
    if target_vertical_bar then
        pcall(function()
            target_vertical_bar:call("SetVisibility", 2) -- Hidden
        end)
    end

    -- 3. 水平バー（LandingGuideHorizontal）を姿勢角で駆動！
    if target_horizontal_bar then
        local att = get_attitude()
        local roll_deg = 0.0
        local pitch_y = 0.0

        if att then
            roll_deg = -att.roll
            local pitch_scale = 10.0
            pitch_y = att.pitch * pitch_scale
        end

        local ok, err = pcall(function()
            target_horizontal_bar:call("SetVisibility", 0) -- Visible
            target_horizontal_bar:call("SetRenderOpacity", 1.0)
            
            -- 色を鮮やかな蛍光グリーンに強制設定 (FLinearColor)
            target_horizontal_bar:call("SetColorAndOpacity", { R = 0.0, G = 1.0, B = 0.1, A = 1.0 })

            -- ロール回転
            target_horizontal_bar:call("SetRenderTransformAngle", roll_deg)

            -- 上下オフセット
            target_horizontal_bar:call("SetRenderTranslation", { X = 0.0, Y = pitch_y })

            -- サイズをしっかり太く大きく（横3倍、縦2倍）
            target_horizontal_bar:call("SetRenderScale", { X = 3.5, Y = 2.5 })
        end)

        if not tick_logged then
            tick_logged = true
            if ok then
                log_txt("Tick loop running successfully! Att: " .. (att and string.format("P=%.1f R=%.1f", att.pitch, att.roll) or "nil"))
            else
                log_txt("Tick loop ERROR: " .. tostring(err))
            end
        end
    end
end)
