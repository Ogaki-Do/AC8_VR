-- test_draw_debug_line.lua
-- Unreal Engine組み込みの3Dデバッグ描画（DrawDebugLine）を用いた人工水平儀テスト
-- 既存のUIパーツを一切変更せず、コックピットHUDガラスに直接3D空間ラインを描画する

local api = uevr.api
if api == nil then return end

local function safe_call(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local kismet_class = api:find_uobject("Class /Script/Engine.KismetSystemLibrary")
local kismet = nil
if kismet_class then
    kismet = kismet_class:get_class_default_object()
end

local logged_info = false

-- プレイヤーPawnと姿勢の取得
local function get_pawn_and_transform()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    if not pawn then return nil, nil, nil end

    local root = pawn.RootComponent
    if not root then return nil, nil, nil end

    local loc = root.RelativeLocation or root:call("K2_GetComponentLocation")
    local rot = root.RelativeRotation or root:call("K2_GetComponentRotation")

    return pawn, loc, rot, root
end

-- 毎フレームの3D描画
uevr.sdk.callbacks.on_post_engine_tick(function()
    local pawn, loc, rot, root = get_pawn_and_transform()
    if not pawn or not loc or not rot or not root then return end

    if not logged_info then
        logged_info = true
        print(string.format("[DrawDebugLine] Pawn found: %s", pawn:get_full_name()))
    end

    -- 機体の前方・右方・上方ベクトル
    local forward = root:call("GetForwardVector")
    local right = root:call("GetRightVector")
    local up = root:call("GetUpVector")
    if not forward or not right or not up then return end

    -- コックピットHUDガラスの位置（パイロットの前方 約 85cm、上方 約 25cm）
    -- 単位はcm（Unreal Engine標準）
    local hud_dist = 85.0
    local hud_height = 25.0
    local bar_width = 18.0 -- 左右の長さ（cm）

    local cx = loc.X + forward.X * hud_dist + up.X * hud_height
    local cy = loc.Y + forward.Y * hud_dist + up.Y * hud_height
    local cz = loc.Z + forward.Z * hud_dist + up.Z * hud_height

    -- 水平バーの左端と右端
    local p_left = {
        X = cx - right.X * bar_width,
        Y = cy - right.Y * bar_width,
        Z = cz - right.Z * bar_width,
    }
    local p_right = {
        X = cx + right.X * bar_width,
        Y = cy + right.Y * bar_width,
        Z = cz + right.Z * bar_width,
    }

    -- 鮮やかな蛍光グリーン (FLinearColor: R, G, B, A)
    local green = { R = 0.0, G = 1.0, B = 0.1, A = 1.0 }

    -- DrawDebugLine(WorldContextObject, LineStart, LineEnd, LineColor, Duration, Thickness)
    if kismet then
        pcall(function()
            kismet:call("DrawDebugLine", pawn, p_left, p_right, green, 0.0, 3.0)
        end)
    end
end)
