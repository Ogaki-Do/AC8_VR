-- ac8_hud_horizon_speed.lua (Robust v8)
-- 『ACE COMBAT 8』UEVR 人工水平儀 ＆ リアルタイムHUD速度インジケーター
-- 修正：クラッシュした診断コードを完全撤去し、水平儀を完全復活！
-- 新機能：Imageによる確実なHUD速度バー（レティクル左横に速度連動ゲージ）を実装！

local api = uevr.api
if api == nil then return end

local log_file = "data/hud_horizon_speed_log.txt"
local function log_txt(str)
    local f = io.open(log_file, "a")
    if f then
        f:write(os.date("%H:%M:%S ") .. tostring(str) .. "\n")
        f:close()
    end
end

pcall(function()
    local f = io.open(log_file, "w")
    if f then f:write("=== AC8 Horizon & Speed HUD (Robust v8) Started ===\n"); f:close() end
end)

-- キャッシュ変数
local target_guide_parent = nil
local target_horizontal_bar = nil
local target_vertical_bar = nil

local cached = false
local last_pawn_ptr = nil

-- キャッシュリセット
local function reset_cache()
    target_guide_parent = nil
    target_horizontal_bar = nil
    target_vertical_bar = nil
    cached = false
    last_pawn_ptr = nil
    log_txt("Scene Reset.")
end

-- パーツ探索（画面上の実行時インスタンスのみ取得）
local function find_hud_elements()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return false end

    local all_w = widget_class:get_objects_matching(false) or {}
    for _, w in ipairs(all_w) do
        local fname = w:get_full_name()
        if fname:find("Transient", 1, true) and not fname:find("Default__", 1, true) and fname:find("MainFlight", 1, true) then
            local sname = fname:match("([^.]+)$") or ""
            
            -- 人工水平儀パーツ
            if sname == "LandingGuide" then
                target_guide_parent = w
            elseif sname == "LandingGuideHorizontal" then
                target_horizontal_bar = w
            elseif sname == "LandingGuideVertical" then
                target_vertical_bar = w
            end
        end
    end

    if target_horizontal_bar then
        cached = true
        log_txt(string.format("Bound: Horiz=%s, Vert=%s", 
            tostring(target_horizontal_bar ~= nil), tostring(target_vertical_bar ~= nil)))
        return true
    end
    return false
end

-- 姿勢角
local function get_attitude(pawn)
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

-- 物理速度（ノット: kt）の計算
local function get_speed_knots(pawn)
    if not pawn then return 0 end
    local vel = pawn:call("GetVelocity")
    if not vel and pawn.RootComponent then
        vel = pawn.RootComponent:call("GetComponentVelocity")
    end
    if vel then
        local vx = vel.X or vel.x or 0.0
        local vy = vel.Y or vel.y or 0.0
        local vz = vel.Z or vel.z or 0.0
        local speed_cms = math.sqrt(vx * vx + vy * vy + vz * vz)
        return math.floor(speed_cms * 0.0194384 + 0.5)
    end
    return 0
end

-- シーン検証
local function validate_scene(pawn)
    if not pawn then
        if cached then reset_cache() end
        return false
    end

    if last_pawn_ptr ~= pawn then
        if last_pawn_ptr ~= nil then reset_cache() end
        last_pawn_ptr = pawn
    end

    local pc = api:get_player_controller(0)
    if pc then
        local ok, is_paused = pcall(function() return pc:call("IsPaused") end)
        if ok and is_paused == true then return false end
    end

    return true
end

-- メインループ
uevr.sdk.callbacks.on_post_engine_tick(function()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    if not validate_scene(pawn) then return end

    if not cached then
        if not find_hud_elements() then return end
    end

    local att = get_attitude(pawn)
    local speed_kt = get_speed_knots(pawn)

    -- =========================================================================
    -- 1. 人工水平儀（HUDガラス内ジャストフィット）
    -- =========================================================================
    if target_guide_parent then
        pcall(function()
            target_guide_parent:call("SetVisibility", 0) -- 0 = Visible
            target_guide_parent:call("SetRenderOpacity", 1.0)
        end)
    end

    if target_horizontal_bar then
        local roll_deg = 0.0
        local pitch_y = 0.0
        local is_climbing = true

        if att then
            roll_deg = -att.roll
            local pitch_scale = 7.0
            pitch_y = att.pitch * pitch_scale
            is_climbing = (att.pitch >= 0.0)
        end

        pcall(function()
            target_horizontal_bar:call("SetVisibility", 0)
            target_horizontal_bar:call("SetRenderOpacity", 1.0)

            if is_climbing then
                target_horizontal_bar:call("SetColorAndOpacity", { R = 0.0, G = 1.0, B = 0.1, A = 1.0 })
            else
                target_horizontal_bar:call("SetColorAndOpacity", { R = 0.2, G = 0.9, B = 0.6, A = 1.0 })
            end

            target_horizontal_bar:call("SetRenderTransformAngle", roll_deg)
            target_horizontal_bar:call("SetRenderTranslation", { X = 0.0, Y = pitch_y })
            target_horizontal_bar:call("SetRenderScale", { X = 1.3, Y = 1.6 })
        end)
    end

    -- =========================================================================
    -- 2. リアルタイムHUD速度インジケーター（レティクル左横のスピードテープ）
    -- =========================================================================
    -- 確実に表示できる垂直バー（Image）を、レティクルの左横（HUD速度計位置）に配置！
    -- 速度（kt）に応じて上下にスライドし、加速・減速がひと目でわかる！
    if target_vertical_bar then
        pcall(function()
            target_vertical_bar:call("SetVisibility", 0)
            target_vertical_bar:call("SetRenderOpacity", 0.9)
            target_vertical_bar:call("SetColorAndOpacity", { R = 0.0, G = 1.0, B = 0.2, A = 0.9 })

            -- 速度連動（基準速度 350kt で中央、加速で上へ、減速で下へ）
            -- 10ktあたり約3ピクセルの上下スライド
            local speed_offset_y = (350 - speed_kt) * 0.4
            -- レティクル左横（X = -130px）に直立バーとして配置
            target_vertical_bar:call("SetRenderTransformAngle", 0.0) -- 機体軸固定
            target_vertical_bar:call("SetRenderTranslation", { X = -130.0, Y = speed_offset_y })
            target_vertical_bar:call("SetRenderScale", { X = 1.8, Y = 1.2 })
        end)
    end
end)
