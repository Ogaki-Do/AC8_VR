-- test_horizon_m1_m2.lua
-- 解決策1（テキストバー）と 解決策2（単色矩形バー）の同時表示テストスクリプト
-- ゲーム本体の生きているUMGパイプラインを直接駆動し、メニューを閉じてもHMDに常時表示させる

local api = uevr.api
if api == nil then return end

local function safe_call(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

-- ログ記録
local function log_txt(str)
    local f = io.open("data/m1_m2_test_log.txt", "a")
    if f then
        f:write(os.date("%H:%M:%S") .. " " .. tostring(str) .. "\n")
        f:close()
    end
end
pcall(function()
    local f = io.open("data/m1_m2_test_log.txt", "w")
    if f then f:write("=== M1/M2 Horizon Test Started ===\n"); f:close() end
end)

-- 機体姿勢取得
local function get_attitude()
    local pawn = api:get_player_pawn(0) or api:get_local_pawn(0)
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

-- 対象ウィジェットのキャッシュ
local m1_text_widget = nil
local m2_bar_left = nil
local m2_bar_right = nil
local cached = false

local function find_widgets()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return end

    local all_w = widget_class:get_objects_matching(false) or {}
    for _, w in ipairs(all_w) do
        local fname = w:get_full_name()
        if fname:find("HUD_Chronicle", 1, true) or fname:find("MainFlight", 1, true) then
            local sname = fname:match("([^.]+)$") or ""
            
            -- [解決策 1 用] テキストブロック（予備または既存テキスト）
            if not m1_text_widget then
                if sname == "TextBlock_SW" or sname == "TextBlock_5" or sname == "TextBlock_9" or sname == "ScoreUpdateText" then
                    m1_text_widget = w
                    log_txt("M1 TextWidget 補足: " .. sname)
                end
            end

            -- [解決策 2 用] 単色ラインパーツ（Neutral_L, PitchBarLeft, PitchBarRight 等）
            if sname == "PitchBarLeft" or sname == "Neutral_L" or sname == "Left_Frame" then
                if not m2_bar_left then
                    m2_bar_left = w
                    log_txt("M2 BarLeft 補足: " .. sname)
                end
            end
            if sname == "PitchBarRight" or sname == "Neutral_R" or sname == "Right_Frame" then
                if not m2_bar_right then
                    m2_bar_right = w
                    log_txt("M2 BarRight 補足: " .. sname)
                end
            end
        end
    end
    cached = true
end

-- 毎フレームのリアルタイム駆動 (on_post_engine_tick)
-- ゲームエンジンと同じタイミングで更新するため、遅延なく常時HMDに映る
uevr.sdk.callbacks.on_post_engine_tick(function()
    if not cached then
        safe_call(find_widgets)
    end

    local att = safe_call(get_attitude)
    if not att then return end

    local roll_deg = -att.roll
    local pitch_deg = att.pitch
    local pitch_scale = 10.0 -- 1度あたりの移動ピクセル
    local pitch_y = pitch_deg * pitch_scale

    -- =====================================================================
    -- [解決策 1] テキスト水平バーの駆動
    -- =====================================================================
    if m1_text_widget then
        safe_call(function()
            -- 表示を強制ON
            m1_text_widget:call("SetVisibility", 0) -- 0 = Visible
            m1_text_widget:call("SetRenderOpacity", 1.0)

            -- テキスト内容をリアルタイム更新 (角度数値付き)
            local sign = (pitch_deg >= 0) and "+" or ""
            local txt = string.format("━━━━━ [ %s%.1f° ] ━━━━━", sign, pitch_deg)
            m1_text_widget:call("SetText", txt)

            -- ロール回転適用
            m1_text_widget:call("SetRenderTransformAngle", roll_deg)

            -- 画面中央基準の上下オフセット移動（FVector2D: X, Y）
            m1_text_widget:call("SetRenderTranslation", { X = 0.0, Y = pitch_y })

            -- サイズを少し見やすく拡大
            m1_text_widget:call("SetRenderScale", { X = 1.6, Y = 1.6 })
        end)
    end

    -- =====================================================================
    -- [解決策 2] 単色矩形バー（物理ライン）の駆動
    -- =====================================================================
    if m2_bar_left then
        safe_call(function()
            m2_bar_left:call("SetVisibility", 0)
            m2_bar_left:call("SetRenderOpacity", 1.0)
            m2_bar_left:call("SetRenderTransformAngle", roll_deg)
            -- 中央から少し左に離して上下動
            m2_bar_left:call("SetRenderTranslation", { X = -80.0, Y = pitch_y + 30.0 })
            m2_bar_left:call("SetRenderScale", { X = 3.0, Y = 1.5 })
        end)
    end

    if m2_bar_right then
        safe_call(function()
            m2_bar_right:call("SetVisibility", 0)
            m2_bar_right:call("SetRenderOpacity", 1.0)
            m2_bar_right:call("SetRenderTransformAngle", roll_deg)
            -- 中央から少し右に離して上下動
            m2_bar_right:call("SetRenderTranslation", { X = 80.0, Y = pitch_y + 30.0 })
            m2_bar_right:call("SetRenderScale", { X = 3.0, Y = 1.5 })
        end)
    end
end)
