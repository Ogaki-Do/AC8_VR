-- ============================================================================
-- ac8_jhmcs_core.lua : JHMCS 360°視線トラッキング & 視線ロック コアモジュール
--   機能:
--     1. 360度カメラ制限完全解除 (ATPC & PlayerCameraManager クランプ解除)
--     2. HMD姿勢に合わせた PlayerController:SetControlRotation 同期
--     3. 視線ロック (Gaze Lock) : 目線中央 (±25°) に捉えた敵機を優先自動ロック
--     4. 武器FCSシーカー角度の全方位 (180°) 拡張 (オフボアサイトミサイルロック)
--     5. JHMCS ヘルメットバイザー HUD 描画 (360°全周ターゲットボックス & センターレティクル)
-- ============================================================================

local api = uevr.api
if api == nil then return nil end

local M = {}

local SCRIPT_NAME    = "AC8-JHMCS-v1"
local LOG_FILE_PATH  = "data/ac8_jhmcs_log.txt"
local GAZE_CONE_DEG  = 25.0    -- 視線ロック有効角度（±25度）
local LOG_EVERY_N    = 60      -- 診断ログ頻度（約1秒毎）

local log_file = nil
local pcall_ok, f = pcall(function() return io.open(LOG_FILE_PATH, "a") end)
if pcall_ok and f then log_file = f end

local function jlog(fmt, ...)
    local msg = string.format(fmt, ...)
    print(string.format("[%s] %s", SCRIPT_NAME, msg))
    if log_file then
        pcall(function()
            log_file:write(string.format("[%s] %s\n", os.date("%H:%M:%S"), msg))
            log_file:flush()
        end)
    end
end

M.jlog = jlog

-- ============================================================================
-- 状態管理
-- ============================================================================
local S = {
    frame = 0,
    is_in_flight = false,
    
    -- HMD姿勢（cm & 度）
    head_pos = { x = 0, y = 0, z = 0 },
    head_rot = { pitch = 0, yaw = 0, roll = 0 },
    gaze_fwd = { x = 1, y = 0, z = 0 },
    gaze_right = { x = 0, y = 1, z = 0 },
    gaze_up = { x = 0, y = 0, z = 1 },

    -- プレイヤー機体 & コンポーネント
    pawn = nil,
    focus_comp = nil,
    target_comps = {},
    camera_comps = {},

    -- ロック対象
    current_target_actor = nil,
    current_target_loc = nil,
    current_target_dist = 0,
    current_target_angle = 999,

    -- 視線候補
    gaze_best_actor = nil,
    gaze_best_loc = nil,
    gaze_best_dist = 0,
    gaze_best_angle = 999,
    gaze_best_name = "",

    -- 全敵機
    active_enemies = {},
}

M.S = S

local function obj_name(obj)
    if not obj then return "None" end
    local ok, fn = pcall(function() return obj:get_full_name() end)
    if ok and fn then
        return fn:match("([^.]+)$") or fn
    end
    return tostring(obj)
end

local function deg2rad(d) return d * (math.pi / 180.0) end
local function rad2deg(r) return r * (180.0 / math.pi) end

local function update_gaze_vectors(pitch_deg, yaw_deg, roll_deg)
    local p = deg2rad(pitch_deg)
    local y = deg2rad(yaw_deg)
    local r = deg2rad(roll_deg)

    local cp, sp = math.cos(p), math.sin(p)
    local cy, sy = math.cos(y), math.sin(y)
    local cr, sr = math.cos(r), math.sin(r)

    -- Unreal Engine: X=前, Y=右, Z=上
    S.gaze_fwd.x = cp * cy
    S.gaze_fwd.y = cp * sy
    S.gaze_fwd.z = sp

    S.gaze_right.x = (sr * sp * cy) - (cr * sy)
    S.gaze_right.y = (sr * sp * sy) + (cr * cy)
    S.gaze_right.z = -sr * cp

    S.gaze_up.x = -(cr * sp * cy) - (sr * sy)
    S.gaze_up.y = -(cr * sp * sy) + (sr * cy)
    S.gaze_up.z = cr * cp
end

M.update_gaze_vectors = update_gaze_vectors

-- ============================================================================
-- フライト状態判定
-- ============================================================================
local function check_flight_active()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    if not pawn then
        S.pawn = nil
        S.is_in_flight = false
        return false
    end

    local pname = pawn:get_full_name() or ""
    if pname:find("Hangar", 1, true) or pname:find("Menu", 1, true) or pname:find("DefaultPawn", 1, true) then
        S.pawn = nil
        S.is_in_flight = false
        return false
    end

    S.pawn = pawn
    S.is_in_flight = true
    return true
end

-- ============================================================================
-- 360度カメラ制限完全解除 & UEVR設定適用
-- ============================================================================
local function unclamp_camera_and_apply_uevr_params()
    -- 1. UEVR 内部設定をメモリ上で Head Aim / UI_FollowView=false に適用
    pcall(function()
        local vr = uevr and uevr.params and uevr.params.vr
        if vr and vr.set_mod_value then
            vr:set_mod_value("VR_AimMethod", "1")
            vr:set_mod_value("VR_AimModifyPlayerControlRotation", "true")
            vr:set_mod_value("VR_DecoupledPitch", "false")
            vr:set_mod_value("UI_FollowView", "false")
            vr:set_mod_value("UI_Cylinder_Angle", "360.000000")
        end
    end)

    -- 2. ATPC & ゲームエンジン CVar 解除（360度首振り & 画面外描画）
    pcall(function()
        api:execute_command("ATPC.CameraMode.RotationSettings.ViewYawMin -180.0")
        api:execute_command("ATPC.CameraMode.RotationSettings.ViewYawMax 180.0")
        api:execute_command("ATPC.CameraMode.RotationSettings.ViewPitchMin -89.9")
        api:execute_command("ATPC.CameraMode.RotationSettings.ViewPitchMax 89.9")
        api:execute_command("ATPC.CameraMode.LockOnTargetSettings.bClampByCameraModeRotationLimits 0")
        api:execute_command("ATPC.CameraMode.LockOnTargetSettings.RotateCameraByYaw 1")
        api:execute_command("ATPC.CameraMode.LockOnTargetSettings.RotateCameraByPitch 1")
        api:execute_command("ATPC.CameraMode.LockOnTargetSettings.bUseDesiredConeRotation 0")
        api:execute_command("ace.HUD.ForceDrawOffscreenInfo 1")
    end)

    -- 3. PlayerCameraManager の首振り制限完全開放
    pcall(function()
        local pc = api:get_player_controller(0)
        if pc and pc.PlayerCameraManager then
            local pcm = pc.PlayerCameraManager
            pcm.ViewYawMin = -180.0
            pcm.ViewYawMax = 180.0
            pcm.ViewPitchMin = -89.9
            pcm.ViewPitchMax = 89.9
        end
    end)

    -- 4. 機体カメラコンポーネントの制限解除
    if S.pawn then
        pcall(function()
            local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
            local comps = S.pawn:call("K2_GetComponentsByClass", actor_comp_class) or {}
            for _, c in ipairs(comps) do
                local cname = c:get_full_name() or ""
                if cname:find("Camera", 1, true) or cname:find("Cockpit", 1, true) then
                    pcall(function() c.ViewYawMin = -180.0 end)
                    pcall(function() c.ViewYawMax = 180.0 end)
                    pcall(function() c.ViewPitchMin = -89.9 end)
                    pcall(function() c.ViewPitchMax = 89.9 end)
                    pcall(function() c.YawLimit = 180.0 end)
                    pcall(function() c.bClampYaw = false end)
                    pcall(function() c.bClampPitch = false end)
                end
                -- ターゲット関連コンポーネントの収集
                if cname:find("Target", 1, true) or cname:find("Focus", 1, true) then
                    table.insert(S.target_comps, c)
                    if cname:find("FocusTarget", 1, true) then S.focus_comp = c end
                end
            end
        end)
    end
end

-- ============================================================================
-- 敵機スキャン & 視線候補検出
-- ============================================================================
local function scan_targets()
    if not S.is_in_flight or not S.pawn then return end

    -- 1. 現在の公式ロック対象の取得
    S.current_target_actor = nil
    S.current_target_loc = nil

    if S.focus_comp then
        pcall(function()
            local ft = S.focus_comp.FocusTarget or S.focus_comp.OverrideFocusTarget
            if ft then
                S.current_target_actor = ft
                local loc = ft:call("K2_GetActorLocation")
                if loc then S.current_target_loc = { x = loc.X, y = loc.Y, z = loc.Z } end
            end
        end)
    end

    -- 2. 全Pawnの探索
    local enemies = {}
    pcall(function()
        local pawn_class = api:find_uobject("Class /Script/Engine.Pawn")
        if pawn_class then
            local all_pawns = pawn_class:get_objects_matching(false) or {}
            for _, p in ipairs(all_pawns) do
                if p ~= S.pawn then
                    local pname = p:get_full_name() or ""
                    -- パイロット・自機内部モデルは除外
                    if not pname:find("PI101", 1, true) and not pname:find("Pilot", 1, true) then
                        local ok_loc, eloc = pcall(function() return p:call("K2_GetActorLocation") end)
                        if ok_loc and eloc and (math.abs(eloc.X) > 1 or math.abs(eloc.Y) > 1) then
                            table.insert(enemies, { actor = p, loc = { x = eloc.X, y = eloc.Y, z = eloc.Z }, name = pname })
                        end
                    end
                end
            end
        end
    end)
    S.active_enemies = enemies

    -- 3. 視線角（Gaze Angle）の計算
    local best_actor, best_loc, best_name = nil, nil, ""
    local best_angle = 999.0
    local best_dist = 0

    local hx, hy, hz = S.head_pos.x, S.head_pos.y, S.head_pos.z
    local gfx, gfy, gfz = S.gaze_fwd.x, S.gaze_fwd.y, S.gaze_fwd.z

    for _, e in ipairs(enemies) do
        local dx = e.loc.x - hx
        local dy = e.loc.y - hy
        local dz = e.loc.z - hz
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist > 3000.0 then -- 30m以上の実機
            local dirx = dx / dist
            local diry = dy / dist
            local dirz = dz / dist
            local dot = dirx * gfx + diry * gfy + dirz * gfz
            local angle = rad2deg(math.acos(math.max(-1.0, math.min(1.0, dot))))
            e.angle = angle
            e.dist = dist
            e.dir = { x = dirx, y = diry, z = dirz }

            if angle < best_angle then
                best_angle = angle
                best_actor = e.actor
                best_loc = e.loc
                best_dist = dist
                best_name = e.name:match("([^.]+)$") or e.name
            end
        end
    end

    S.gaze_best_actor = best_actor
    S.gaze_best_loc = best_loc
    S.gaze_best_angle = best_angle
    S.gaze_best_dist = best_dist
    S.gaze_best_name = best_name

    -- 現在ロック対象の角度計算
    if S.current_target_loc then
        local dx = S.current_target_loc.x - hx
        local dy = S.current_target_loc.y - hy
        local dz = S.current_target_loc.z - hz
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist > 50.0 then
            local dot = (dx/dist)*gfx + (dy/dist)*gfy + (dz/dist)*gfz
            S.current_target_angle = rad2deg(math.acos(math.max(-1.0, math.min(1.0, dot))))
            S.current_target_dist = dist
        end
    else
        S.current_target_angle = 999.0
        S.current_target_dist = 0
    end
end

-- ============================================================================
-- 視線ロック（Gaze Lock）実行
-- ============================================================================
local function apply_gaze_lock()
    if not S.is_in_flight then return end

    -- 目線中心から GAZE_CONE_DEG 以内にいる敵機を自動ロック
    if S.gaze_best_actor and S.gaze_best_angle <= GAZE_CONE_DEG then
        if S.gaze_best_actor ~= S.current_target_actor then
            -- 1. FocusTargetComponent
            if S.focus_comp then
                pcall(function() S.focus_comp.OverrideFocusTarget = S.gaze_best_actor end)
                pcall(function() S.focus_comp.FocusTarget = S.gaze_best_actor end)
            end

            -- 2. 全ターゲット系コンポーネントに伝達
            for _, tc in ipairs(S.target_comps) do
                pcall(function() tc.SelectedTarget = S.gaze_best_actor end)
                pcall(function() tc.CurrentTarget = S.gaze_best_actor end)
                pcall(function() tc.TargetActor = S.gaze_best_actor end)
                pcall(function() tc:call("StartSelectTarget", S.gaze_best_actor) end)
                pcall(function() tc:call("SelectTarget", S.gaze_best_actor) end)
            end

            -- 3. PlayerController / Pawn のターゲット切り替え関数呼び出し
            pcall(function()
                local pc = api:get_player_controller(0)
                if pc then
                    pc:call("TargetChange")
                    pc:call("OnChangeTarget")
                end
            end)

            jlog("★ 360°視線ロック成立！ 角度=%.1f° 距離=%.0fm ターゲット=%s",
                S.gaze_best_angle, S.gaze_best_dist / 100.0, S.gaze_best_name)
        end
    end
end

-- ============================================================================
-- 武器FCSシーカー角度の全方位 (180°) 拡張
-- ============================================================================
local function expand_weapon_fcs()
    pcall(function()
        local weapon_class = api:find_uobject("Class /Script/Live.LiveWeaponBase")
        if weapon_class then
            local weapons = weapon_class:get_objects_matching(false) or {}
            for _, w in ipairs(weapons) do
                pcall(function()
                    if w.FCSAngleLimit and w.FCSAngleLimit < 180.0 then w.FCSAngleLimit = 180.0 end
                    if w.SeekerFOV and w.SeekerFOV < 180.0 then w.SeekerFOV = 180.0 end
                    if w.LockAngle and w.LockAngle < 180.0 then w.LockAngle = 180.0 end
                    if w.GimbalLimit and w.GimbalLimit < 180.0 then w.GimbalLimit = 180.0 end
                    w.bOffBoresight = true
                    w.bAllAspect = true
                end)
            end
        end
    end)
end

-- ============================================================================
-- JHMCS ヘルメットバイザー HUD 描画 (360°全周ターゲットボックス)
-- ============================================================================
local function on_draw_jhmcs_hud()
    if not S.is_in_flight then return end

    local io = imgui.get_io()
    local disp_w = io.DisplaySize.x or 1920
    local disp_h = io.DisplaySize.y or 1080

    local cx = disp_w * 0.5
    local cy = disp_h * 0.5
    local focal = disp_w * 0.5 -- 視野角約90度に対応する焦点距離

    -- 透明な全画面ウィンドウでDrawListを取得
    local flags = 1 + 2 + 4 + 8 + 128 + 512 -- NoTitleBar|NoResize|NoMove|NoScrollbar|NoBackground|NoInputs
    imgui.set_next_window_pos({0, 0})
    imgui.set_next_window_size({disp_w, disp_h})
    imgui.push_style_var(imgui.ImGuiStyleVar.WindowBorderSize, 0.0)

    if imgui.begin_window("AC8_JHMCS_VisorHUD", nil, flags) then
        local dl = imgui.get_window_draw_list()
        local col_green = 0xFF44FF44   -- 通常ターゲット枠（蛍光グリーン）
        local col_lock  = 0xFF00E5FF   -- 視線ロック中（ゴールド/シアン）
        local col_dim   = 0x8844AA44   -- 視野外ガイド（半透明グリーン）

        -- 1. JHMCS センター照準レティクル（視線中心）
        dl:add_circle({cx, cy}, 22, col_green, 16, 1.8)
        dl:add_circle({cx, cy}, 3, col_green, 8, 1.8)
        dl:add_line({cx - 10, cy}, {cx - 4, cy}, col_green, 1.5)
        dl:add_line({cx + 4, cy}, {cx + 10, cy}, col_green, 1.5)
        dl:add_line({cx, cy - 10}, {cx, cy - 4}, col_green, 1.5)
        dl:add_line({cx, cy + 4}, {cx, cy + 10}, col_green, 1.5)

        -- 2. 敵機ターゲットボックスの描画（360度対応・HMDローカル投影）
        local hx, hy, hz = S.head_pos.x, S.head_pos.y, S.head_pos.z
        local gfx, gfy, gfz = S.gaze_fwd.x, S.gaze_fwd.y, S.gaze_fwd.z
        local grx, gry, grz = S.gaze_right.x, S.gaze_right.y, S.gaze_right.z
        local gux, guy, guz = S.gaze_up.x, S.gaze_up.y, S.gaze_up.z

        for _, e in ipairs(S.active_enemies) do
            if e.dist and e.dist > 3000.0 and e.dist < 1500000.0 then -- 30m〜15km
                local dx = e.loc.x - hx
                local dy = e.loc.y - hy
                local dz = e.loc.z - hz
                local dist = e.dist

                -- HMDローカル座標系への射影
                local lx = (dx * gfx + dy * gfy + dz * gfz) / dist
                local ly = (dx * grx + dy * gry + dz * grz) / dist
                local lz = (dx * gux + dy * guy + dz * guz) / dist

                local is_locked = (e.actor == S.gaze_best_actor and S.gaze_best_angle <= GAZE_CONE_DEG)
                local col = is_locked and col_lock or col_green

                if lx > 0.1 then -- 頭部視線の前方視野（約160度以内）
                    local sx = cx + (ly / lx) * focal
                    local sy = cy - (lz / lx) * focal

                    if sx >= 40 and sx <= (disp_w - 40) and sy >= 40 and sy <= (disp_h - 40) then
                        -- スクリーン内：3Dコンフォーマル ターゲットボックス描画
                        local bsize = is_locked and 26 or 20
                        local th = is_locked and 2.5 or 1.8

                        -- 角カッコ [ ]
                        dl:add_line({sx - bsize, sy - bsize}, {sx - bsize + 8, sy - bsize}, col, th)
                        dl:add_line({sx - bsize, sy - bsize}, {sx - bsize, sy - bsize + 8}, col, th)
                        dl:add_line({sx + bsize, sy - bsize}, {sx + bsize - 8, sy - bsize}, col, th)
                        dl:add_line({sx + bsize, sy - bsize}, {sx + bsize, sy - bsize + 8}, col, th)
                        dl:add_line({sx - bsize, sy + bsize}, {sx - bsize + 8, sy + bsize}, col, th)
                        dl:add_line({sx - bsize, sy + bsize}, {sx - bsize, sy + bsize - 8}, col, th)
                        dl:add_line({sx + bsize, sy + bsize}, {sx + bsize - 8, sy + bsize}, col, th)
                        dl:add_line({sx + bsize, sy + bsize}, {sx + bsize, sy + bsize - 8}, col, th)

                        -- ターゲット情報テキスト
                        local sname = e.name:match("([^.]+)$") or e.name
                        local dist_m = math.floor(dist / 100.0)
                        local tag = is_locked and string.format("LOCK [ %s ] %dm", sname, dist_m) or string.format("TGT %s %dm", sname, dist_m)
                        dl:add_text({sx - bsize, sy + bsize + 4}, col, tag)

                        -- ロック中の誘導ライン
                        if is_locked then
                            dl:add_line({cx, cy}, {sx, sy}, col_lock, 1.2)
                        end
                    end
                else
                    -- 視線後方（90〜180度）：視野外インジケーター（矢印＆距離）
                    local norm_r = math.sqrt(ly*ly + lz*lz)
                    if norm_r > 0.01 then
                        local edge_x = cx + (ly / norm_r) * (cx - 60)
                        local edge_y = cy - (lz / norm_r) * (cy - 60)
                        dl:add_circle({edge_x, edge_y}, 10, col_dim, 12, 1.5)
                        dl:add_text({edge_x + 14, edge_y - 8}, col_dim, string.format("%.0fm (%.0f°)", dist / 100.0, e.angle or 180))
                    end
                end
            end
        end

        imgui.pop_style_var()
        imgui.end_window()
    end
end

-- ============================================================================
-- メインフレーム処理
-- ============================================================================
function M.tick()
    S.frame = S.frame + 1

    if not check_flight_active() then return end

    -- 初回または定期的なカメラ・UEVR設定解除
    if S.frame % 60 == 1 then
        unclamp_camera_and_apply_uevr_params()
    end

    -- ターゲット走査
    scan_targets()

    -- ControlRotation を頭部姿勢に完全追従同期（360度制限なし）
    pcall(function()
        local pc = api:get_player_controller(0)
        if pc and S.head_rot then
            pc:SetControlRotation({
                Pitch = math.max(-89.0, math.min(89.0, S.head_rot.pitch)),
                Yaw   = S.head_rot.yaw,
                Roll  = 0
            })
        end
    end)

    -- 武器FCSシーカー全方位開放
    if S.frame % 60 == 0 then
        expand_weapon_fcs()
    end

    -- 視線ロック適用
    apply_gaze_lock()

    -- 診断ログ出力
    if S.frame % LOG_EVERY_N == 0 then
        local cur_str = S.current_target_actor and string.format("%s (%.0fm, 視線差%.1f°)",
            obj_name(S.current_target_actor), S.current_target_dist / 100.0, S.current_target_angle) or "None"

        local gaze_str = S.gaze_best_actor and string.format("%s (%.0fm, 角度%.1f°)",
            S.gaze_best_name, S.gaze_best_dist / 100.0, S.gaze_best_angle) or "None"

        jlog("frame=%d 頭部=(%.1f,%.1f,%.1f)° ロック=[%s] 視線最寄=[%s] 捕捉機数=%d",
            S.frame, S.head_rot.pitch, S.head_rot.yaw, S.head_rot.roll,
            cur_str, gaze_str, #S.active_enemies)
    end
end

M.on_draw_ui = on_draw_jhmcs_hud

return M
