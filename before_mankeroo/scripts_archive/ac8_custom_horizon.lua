-- ac8_custom_horizon.lua
-- ACE COMBAT 8 - 自作VR人工水平儀（HUDオーバーレイ）スクリプト

local api = uevr.api
if api == nil then return end

local function safe_call(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
end

-- 設定パラメータ（ユーザー調整可能）
local config = {
    enabled = true,
    line_color = 0xFF44FF44,       -- ABGR形式: 鮮やかなネオングリーン
    line_thickness = 2.5,          -- 線の太さ
    horizon_half_width = 160.0,    -- 水平線の長さ（片側）
    center_gap = 40.0,             -- 水平線の中央の隙間
    pitch_pixel_scale = 12.0,      -- ピッチ角1度あたりのピクセル移動量
    show_pitch_ladder = true,      -- ±10°, ±20°のピッチ梯子を表示するか
    show_center_cross = true,      -- 中央自機レティクルを表示するか
    show_debug_window = true,      -- 調整用UIウィンドウを表示するか
    offset_x = 0.0,                -- 左右オフセット調整
    offset_y = 0.0,                -- 上下オフセット調整
}

-- 回転行列計算用ヘルパー
local function rotate_point(x, y, angle_rad)
    local c = math.cos(angle_rad)
    local s = math.sin(angle_rad)
    return x * c - y * s, x * s + y * c
end

-- プレイヤー機体から現在の姿勢（Pitch, Roll）を取得
local function get_plane_attitude()
    local pawn = safe_call(function() return api:get_player_pawn(0) or api:get_local_pawn(0) end, nil)
    if not pawn then
        local pc = safe_call(function() return api:get_player_controller(0) end, nil)
        if pc then pawn = safe_call(function() return pc.Pawn or pc.AcknowledgedPawn end, nil) end
    end
    if not pawn then return nil end

    -- 機体の回転を取得
    local rot = safe_call(function() return pawn:call("K2_GetActorRotation") end, nil)
    if not rot then
        local root = safe_call(function() return pawn.RootComponent end, nil)
        if root then
            rot = safe_call(function() return root.RelativeRotation end, nil)
        end
    end

    if rot then
        local p = rot.Pitch or rot.pitch or 0.0
        local r = rot.Roll or rot.roll or 0.0
        local y = rot.Yaw or rot.yaw or 0.0
        return { pitch = p, roll = r, yaw = y }
    end
    return nil
end

-- 描画コールバック
local function on_draw_ui()
    -- 1. 調整用UIウィンドウ（UEVRメニュー内などに表示）
    if config.show_debug_window then
        if imgui.begin_window("AC8 自作水平儀 設定", nil, 0) then
            local changed_en, en = imgui.checkbox("水平儀を有効化", config.enabled)
            if changed_en then config.enabled = en end

            local changed_l, l = imgui.checkbox("±10/20度 ピッチラダー表示", config.show_pitch_ladder)
            if changed_l then config.show_pitch_ladder = l end

            local changed_c, c = imgui.checkbox("中央クロスヘア表示", config.show_center_cross)
            if changed_c then config.show_center_cross = c end

            local changed_s, s = imgui.slider_float("ピッチ感度 (上下移動量)", config.pitch_pixel_scale, 2.0, 30.0)
            if changed_s then config.pitch_pixel_scale = s end

            local changed_ox, ox = imgui.slider_float("中心位置 X調整", config.offset_x, -300.0, 300.0)
            if changed_ox then config.offset_x = ox end

            local changed_oy, oy = imgui.slider_float("中心位置 Y調整", config.offset_y, -300.0, 300.0)
            if changed_oy then config.offset_y = oy end

            -- 現在の姿勢のリアルタイム表示
            local att = get_plane_attitude()
            if att then
                imgui.text(string.format("現在機体姿勢 -> Pitch: %.1f deg | Roll: %.1f deg", att.pitch, att.roll))
            else
                imgui.text("機体データ待機中 (出撃中に検出されます)")
            end

            imgui.end_window()
        end
    end

    if not config.enabled then return end

    local att = get_plane_attitude()
    if not att then return end

    -- 画面サイズの取得
    local io = imgui.get_io()
    local disp_w = io.DisplaySize.x or 1920
    local disp_h = io.DisplaySize.y or 1080

    -- 画面中央
    local cx = (disp_w * 0.5) + config.offset_x
    local cy = (disp_h * 0.5) + config.offset_y

    -- 透明な全画面ウィンドウを作ってDrawListで描画
    -- ImGuiWindowFlags: NoTitleBar(1) + NoResize(2) + NoMove(4) + NoScrollbar(8) + NoInputs(512) + NoBackground(128) = 655
    local flags = 1 + 2 + 4 + 8 + 128 + 512
    imgui.set_next_window_pos({0, 0})
    imgui.set_next_window_size({disp_w, disp_h})
    imgui.push_style_var(imgui.ImGuiStyleVar.WindowBorderSize, 0.0)

    if imgui.begin_window("AC8_HUD_Overlay", nil, flags) then
        local dl = imgui.get_window_draw_list()
        local col = config.line_color
        local th = config.line_thickness

        -- 自機中心レティクル（小さな十字 / 自機シンボル）
        if config.show_center_cross then
            dl:add_line({cx - 15, cy}, {cx - 5, cy}, col, th)
            dl:add_line({cx + 5, cy}, {cx + 15, cy}, col, th)
            dl:add_line({cx, cy - 10}, {cx, cy - 3}, col, th)
            dl:add_circle({cx, cy}, 3, col, 12, th)
        end

        -- 機体のピッチとロール
        -- 右ロールで水平線は反時計回りに傾く（-roll）
        local roll_rad = math.rad(-att.roll)
        local pitch_deg = att.pitch

        -- 水平線の上下移動オフセット（ピッチがプラス＝機首上げなら水平線は下に移動）
        local pitch_y_offset = pitch_deg * config.pitch_pixel_scale

        -- 1. 主人工水平線（Horizon Line: 左右のバー）
        local function draw_horizon_segment(x1, x2, y_offset, is_dashed)
            -- 回転前のローカル座標
            local lx1, ly1 = x1, y_offset
            local lx2, ly2 = x2, y_offset

            -- ロール回転適用
            local rx1, ry1 = rotate_point(lx1, ly1, roll_rad)
            local rx2, ry2 = rotate_point(lx2, ly2, roll_rad)

            -- スクリーン中央に配置
            dl:add_line({cx + rx1, cy + ry1}, {cx + rx2, cy + ry2}, col, th)
        end

        -- 左水平線、右水平線
        draw_horizon_segment(-config.horizon_half_width, -config.center_gap, pitch_y_offset, false)
        draw_horizon_segment(config.center_gap, config.horizon_half_width, pitch_y_offset, false)

        -- 2. ピッチラダー（±10度、±20度）
        if config.show_pitch_ladder then
            local ladder_angles = { -20, -10, 10, 20 }
            local ladder_w = 60.0
            local ladder_gap = 30.0
            local notch_h = 10.0

            for _, deg in ipairs(ladder_angles) do
                -- 自機ピッチに対する相対位置
                local rel_deg = pitch_deg - deg
                local ladder_y = rel_deg * config.pitch_pixel_scale

                -- 画面内にある時だけ描画
                if math.abs(ladder_y) < (disp_h * 0.45) then
                    -- 左右のバー
                    draw_horizon_segment(-ladder_w, -ladder_gap, ladder_y, false)
                    draw_horizon_segment(ladder_gap, ladder_w, ladder_y, false)

                    -- 端のカギ（プラスは下向き、マイナスは上向き）
                    local notch_dir = (deg > 0) and notch_h or -notch_h
                    local n_lx1, n_ly1 = -ladder_w, ladder_y
                    local n_lx2, n_ly2 = -ladder_w, ladder_y + notch_dir
                    local n_rx1, n_ry1 = ladder_w, ladder_y
                    local n_rx2, n_ry2 = ladder_w, ladder_y + notch_dir

                    local r_nx1, r_ny1 = rotate_point(n_lx1, n_ly1, roll_rad)
                    local r_nx2, r_ny2 = rotate_point(n_lx2, n_ly2, roll_rad)
                    local r_rx1, r_ry1 = rotate_point(n_rx1, n_ry1, roll_rad)
                    local r_rx2, r_ry2 = rotate_point(n_rx2, n_ry2, roll_rad)

                    dl:add_line({cx + r_nx1, cy + r_ny1}, {cx + r_nx2, cy + r_ny2}, col, th)
                    dl:add_line({cx + r_rx1, cy + r_ry1}, {cx + r_rx2, cy + r_ry2}, col, th)
                end
            end
        end

        imgui.end_window()
    end
    imgui.pop_style_var()
end

pcall(function()
    uevr.sdk.callbacks.on_draw_ui(on_draw_ui)
end)
