-- ============================================================================
-- AC8_JHMCS_TEST_PLANC.lua : HMD視線基準 360° JHMCS ターゲットマーカー (Plan C)
--   ゲーム: 『ACE COMBAT 8』
--   特徴:
--     1. HUD座標・ゲームカメラには一切触れない（完全ゼロ干渉・安全第一）
--     2. on_post_calculate_stereo_view_offset からHMD位置・姿勢を取得
--     3. HMD視線ベクトルへ3D内積射影してターゲット位置を計算
--     4. on_frame コールバックにより、UEVRメニューを閉じても常時HMD視界上に描画
--     5. 最低限の機能 + 最小限の診断ログのみで構成されたクリーン実装
-- ============================================================================

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME   = "AC8-JHMCS-PlanC"
local LOG_FILE_PATH = "data/ac8_jhmcs_planc_log.txt"

local log_file = nil
local ok_f, f = pcall(function() return io.open(LOG_FILE_PATH, "w") end)
if ok_f and f then
    log_file = f
    log_file:write("================================================================================\n")
    log_file:write("  ACE COMBAT 8 - JHMCS Plan C (HMD基準ターゲット計算) 稼働ログ\n")
    log_file:write("  開始日時: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    log_file:write("================================================================================\n\n")
    log_file:flush()
end

local function clog(fmt, ...)
    local msg = string.format(fmt, ...)
    print(string.format("[%s] %s", SCRIPT_NAME, msg))
    if log_file then
        pcall(function()
            log_file:write(string.format("[%s] %s\n", os.date("%H:%M:%S"), msg))
            log_file:flush()
        end)
    end
end

-- ============================================================================
-- 状態データ (最小構成)
-- ============================================================================
local S = {
    frame = 0,
    hmd_pos = { x = 0.0, y = 0.0, z = 0.0 },
    hmd_rot = { pitch = 0.0, yaw = 0.0, roll = 0.0 },
    hmd_valid = false,

    target_actor = nil,
    target_loc   = nil,
    target_name  = "None",

    last_proj = nil,
}

-- ============================================================================
-- 1. HMD姿勢コールバック (頭部ワールド位置・姿勢の完全取得)
-- ============================================================================
local cbs = uevr.sdk.callbacks
if cbs and cbs.on_post_calculate_stereo_view_offset ~= nil then
    cbs.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
        if position and rotation then
            S.hmd_pos.x = position.x or position.X or 0.0
            S.hmd_pos.y = position.y or position.Y or 0.0
            S.hmd_pos.z = position.z or position.Z or 0.0

            S.hmd_rot.pitch = rotation.x or rotation.Pitch or 0.0
            S.hmd_rot.yaw   = rotation.y or rotation.Yaw   or 0.0
            S.hmd_rot.roll  = rotation.z or rotation.Roll  or 0.0
            S.hmd_valid = true
        end
    end)
end

-- ============================================================================
-- 2. プレイヤー機 & ターゲット敵機の探索 (安全なpcall実装)
-- ============================================================================
local function get_pawn()
    local ok1, p1 = pcall(function() return api:get_local_pawn(0) end)
    if ok1 and p1 then return p1 end

    local ok2, pc = pcall(function() return api:get_player_controller(0) end)
    if ok2 and pc then
        local ok3, p3 = pcall(function() return pc.Pawn or pc.AcknowledgedPawn end)
        if ok3 and p3 then return p3 end
    end
    return nil
end

local function scan_target(pawn)
    if not pawn then return nil, nil, "None" end

    -- ① FocusTargetComponent（ゲームの公式ロック対象）を最優先
    local ok_act, actor_comp_class = pcall(function() return api:find_uobject("Class /Script/Engine.ActorComponent") end)
    if ok_act and actor_comp_class then
        local ok_comps, comps = pcall(function() return pawn:call("K2_GetComponentsByClass", actor_comp_class) end)
        if ok_comps and comps then
            for _, c in ipairs(comps) do
                local cn = ""
                pcall(function() cn = c:get_full_name() or "" end)
                if cn:find("FocusTarget", 1, true) then
                    local ft = nil
                    pcall(function() ft = c.FocusTarget or c.OverrideFocusTarget end)
                    if ft then
                        local ok_l, loc = pcall(function() return ft:call("K2_GetActorLocation") end)
                        if ok_l and loc then
                            local fn = ""
                            pcall(function() fn = ft:get_full_name() or "" end)
                            return ft, { x = loc.X or loc.x, y = loc.Y or loc.y, z = loc.Z or loc.z }, fn
                        end
                    end
                end
            end
        end
    end

    -- ② 未ロック時のフォールバック: 最寄りの敵機Pawn
    local ok_pc, pawn_class = pcall(function() return api:find_uobject("Class /Script/Engine.Pawn") end)
    if ok_pc and pawn_class then
        local ok_m, all_pawns = pcall(function() return pawn_class:get_objects_matching(false) end)
        if ok_m and all_pawns then
            local ok_ploc, p_loc = pcall(function() return pawn:call("K2_GetActorLocation") end)
            local px = (ok_ploc and p_loc) and (p_loc.X or p_loc.x or 0.0) or 0.0
            local py = (ok_ploc and p_loc) and (p_loc.Y or p_loc.y or 0.0) or 0.0
            local pz = (ok_ploc and p_loc) and (p_loc.Z or p_loc.z or 0.0) or 0.0

            local best_p, best_loc, best_dist, best_name = nil, nil, 999999999.0, ""
            for _, p in ipairs(all_pawns) do
                if p ~= pawn then
                    local pn = ""
                    pcall(function() pn = p:get_full_name() or "" end)
                    if not pn:find("Pilot", 1, true) and not pn:find("PI101", 1, true) and not pn:find("DefaultPawn", 1, true) then
                        local ok_l, loc = pcall(function() return p:call("K2_GetActorLocation") end)
                        if ok_l and loc then
                            local lx = loc.X or loc.x or 0.0
                            local ly = loc.Y or loc.y or 0.0
                            local lz = loc.Z or loc.z or 0.0
                            if math.abs(lx) > 1.0 or math.abs(ly) > 1.0 then
                                local dx = lx - px
                                local dy = ly - py
                                local dz = lz - pz
                                local d = math.sqrt(dx*dx + dy*dy + dz*dz)
                                if d > 1000.0 and d < best_dist then
                                    best_dist = d
                                    best_p = p
                                    best_loc = { x = lx, y = ly, z = lz }
                                    best_name = pn
                                end
                            end
                        end
                    end
                end
            end
            if best_p then
                return best_p, best_loc, best_name
            end
        end
    end

    -- ③ ターゲットが完全に不在の場合: 自機前方 200m に仮想テストターゲットを配置
    local ok_root, root = pcall(function() return pawn.RootComponent end)
    if ok_root and root then
        local ok_fwd, fwd = pcall(function() return root:call("GetForwardVector") end)
        local ok_ploc, ploc = pcall(function() return root:call("K2_GetComponentLocation") end)
        if ok_fwd and fwd and ok_ploc and ploc then
            local fx = fwd.X or fwd.x or 1.0
            local fy = fwd.Y or fwd.y or 0.0
            local fz = fwd.Z or fwd.z or 0.0
            local px = ploc.X or ploc.x or 0.0
            local py = ploc.Y or ploc.y or 0.0
            local pz = ploc.Z or ploc.z or 0.0
            return nil, { x = px + fx * 20000.0, y = py + fy * 20000.0, z = pz + fz * 20000.0 }, "SIM-TARGET-200m"
        end
    end

    return nil, nil, "None"
end

-- ============================================================================
-- 3. HMD視線基準の3D幾何射影計算
-- ============================================================================
local function project_target_to_hmd(target_loc)
    if not S.hmd_valid or not target_loc then return nil end

    local deg2rad = math.pi / 180.0
    local p = S.hmd_rot.pitch * deg2rad
    local y = S.hmd_rot.yaw   * deg2rad
    local r = S.hmd_rot.roll  * deg2rad

    local cp, sp = math.cos(p), math.sin(p)
    local cy, sy = math.cos(y), math.sin(y)
    local cr, sr = math.cos(r), math.sin(r)

    -- HMD 視線基底ベクトル (Unreal Engine: X=前, Y=右, Z=上)
    local fx = cp * cy
    local fy = cp * sy
    local fz = sp

    local rx = (sr * sp * cy) - (cr * sy)
    local ry = (sr * sp * sy) + (cr * cy)
    local rz = -sr * cp

    local ux = -(cr * sp * cy) - (sr * sy)
    local uy = -(cr * sp * sy) + (sr * cy)
    local uz = cr * cp

    -- HMDからターゲットへの相対ベクトル
    local dx = target_loc.x - S.hmd_pos.x
    local dy = target_loc.y - S.hmd_pos.y
    local dz = target_loc.z - S.hmd_pos.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    if dist < 1.0 then return nil end

    -- HMDローカル座標系への内積分解
    local lx = dx * fx + dy * fy + dz * fz   -- 視線前方成分 (>0 なら前)
    local ly = dx * rx + dy * ry + dz * rz   -- 視線右方成分
    local lz = dx * ux + dy * uy + dz * uz   -- 視線上方成分

    local dot_fwd = lx / dist
    local angle_deg = math.deg(math.acos(math.max(-1.0, math.min(1.0, dot_fwd))))

    return {
        dist = dist,
        lx = lx,
        ly = ly,
        lz = lz,
        in_front = (lx > 0),
        angle = angle_deg
    }
end

-- ============================================================================
-- 4. メインTick (ターゲット探索 & 射影)
-- ============================================================================
if cbs and cbs.on_post_engine_tick ~= nil then
    cbs.on_post_engine_tick(function()
        S.frame = S.frame + 1

        local pawn = get_pawn()
        if not pawn then
            S.target_actor = nil
            S.target_loc   = nil
            S.last_proj    = nil
            return
        end

        local actor, loc, name = scan_target(pawn)
        S.target_actor = actor
        S.target_loc   = loc
        S.target_name  = name

        if loc then
            S.last_proj = project_target_to_hmd(loc)
        else
            S.last_proj = nil
        end

        if S.frame % 60 == 0 then
            if S.last_proj then
                local dist_m = math.floor(S.last_proj.dist / 100.0)
                local sname = S.target_name:match("([^.]+)$") or S.target_name
                clog("HMD=(P:%+.1f, Y:%+.1f) TGT=[%s] 距離=%dm 視線差=%.1f° (前方=%s, X:%.1f, Y:%.1f, Z:%.1f)",
                    S.hmd_rot.pitch, S.hmd_rot.yaw, sname, dist_m, S.last_proj.angle,
                    tostring(S.last_proj.in_front), S.last_proj.lx, S.last_proj.ly, S.last_proj.lz)
            else
                clog("Tick稼働中: HMD姿勢=(P:%+.1f, Y:%+.1f, R:%+.1f) (ターゲット探索中)",
                    S.hmd_rot.pitch, S.hmd_rot.yaw, S.hmd_rot.roll)
            end
        end
    end)
end

-- ============================================================================
-- 5. JHMCS HUD常時描画 (on_frame: UEVRメニュー開閉に関わらず常時描画)
-- ============================================================================
if cbs and cbs.on_frame ~= nil then
    cbs.on_frame(function()
        if not S.hmd_valid then return end

        pcall(function()
            local io = imgui.get_io()
            local dw = io.DisplaySize.x or 1920.0
            local dh = io.DisplaySize.y or 1080.0
            local cx = dw * 0.5
            local cy = dh * 0.5
            local focal = dw * 0.5

            local flags = 1 + 2 + 4 + 8 + 128 -- NoTitleBar, NoResize, NoMove, NoScrollbar, NoBackground
            imgui.set_next_window_pos({0, 0})
            imgui.set_next_window_size({dw, dh})
            imgui.push_style_var(imgui.ImGuiStyleVar.WindowBorderSize, 0.0)

            if imgui.begin_window("AC8_JHMCS_PlanC_Overlay", nil, flags) then
                local green = 0xFF00FF00
                local cyan  = 0xFF00E5FF
                local dim   = 0x8800AA00

                -- ① 視界中央レティクル（十字 + サークル）
                imgui.draw_list_path_clear()
                imgui.draw_list_path_line_to({cx - 16, cy})
                imgui.draw_list_path_line_to({cx - 4, cy})
                imgui.draw_list_path_stroke(green, false, 2.0)

                imgui.draw_list_path_clear()
                imgui.draw_list_path_line_to({cx + 4, cy})
                imgui.draw_list_path_line_to({cx + 16, cy})
                imgui.draw_list_path_stroke(green, false, 2.0)

                imgui.draw_list_path_clear()
                imgui.draw_list_path_line_to({cx, cy - 16})
                imgui.draw_list_path_line_to({cx, cy - 4})
                imgui.draw_list_path_stroke(green, false, 2.0)

                imgui.draw_list_path_clear()
                imgui.draw_list_path_line_to({cx, cy + 4})
                imgui.draw_list_path_line_to({cx, cy + 16})
                imgui.draw_list_path_stroke(green, false, 2.0)

                -- ② ターゲットマーカー（HMD基準投影）
                if S.last_proj then
                    local dist_m = math.floor(S.last_proj.dist / 100.0)
                    local sname = S.target_name:match("([^.]+)$") or S.target_name

                    if S.last_proj.in_front then
                        -- 視界前方: ターゲットボックス描画
                        local sx = cx + (S.last_proj.ly / S.last_proj.lx) * focal
                        local sy = cy - (S.last_proj.lz / S.last_proj.lx) * focal

                        if sx >= 20 and sx <= (dw - 20) and sy >= 20 and sy <= (dh - 20) then
                            local sz = 24.0

                            -- 左上
                            imgui.draw_list_path_clear()
                            imgui.draw_list_path_line_to({sx - sz + 8, sy - sz})
                            imgui.draw_list_path_line_to({sx - sz, sy - sz})
                            imgui.draw_list_path_line_to({sx - sz, sy - sz + 8})
                            imgui.draw_list_path_stroke(cyan, false, 2.5)

                            -- 右上
                            imgui.draw_list_path_clear()
                            imgui.draw_list_path_line_to({sx + sz - 8, sy - sz})
                            imgui.draw_list_path_line_to({sx + sz, sy - sz})
                            imgui.draw_list_path_line_to({sx + sz, sy - sz + 8})
                            imgui.draw_list_path_stroke(cyan, false, 2.5)

                            -- 左下
                            imgui.draw_list_path_clear()
                            imgui.draw_list_path_line_to({sx - sz + 8, sy + sz})
                            imgui.draw_list_path_line_to({sx - sz, sy + sz})
                            imgui.draw_list_path_line_to({sx - sz, sy + sz - 8})
                            imgui.draw_list_path_stroke(cyan, false, 2.5)

                            -- 右下
                            imgui.draw_list_path_clear()
                            imgui.draw_list_path_line_to({sx + sz - 8, sy + sz})
                            imgui.draw_list_path_line_to({sx + sz, sy + sz})
                            imgui.draw_list_path_line_to({sx + sz, sy + sz - 8})
                            imgui.draw_list_path_stroke(cyan, false, 2.5)

                            -- ターゲット名 & 距離 & 視線角度
                            imgui.set_cursor_screen_pos({sx - sz, sy + sz + 5})
                            imgui.text_colored(string.format("TGT %s %dm (%.0f°)", sname, dist_m, S.last_proj.angle), cyan)
                        end
                    else
                        -- 視界後方（背後・死角）: 画面端に誘導矢印 & 距離インジケーター
                        local norm = math.sqrt(S.last_proj.ly * S.last_proj.ly + S.last_proj.lz * S.last_proj.lz)
                        if norm > 0.01 then
                            local ex = cx + (S.last_proj.ly / norm) * (cx - 70)
                            local ey = cy - (S.last_proj.lz / norm) * (cy - 70)

                            imgui.draw_list_path_clear()
                            imgui.draw_list_path_line_to({ex - 8, ey})
                            imgui.draw_list_path_line_to({ex + 8, ey})
                            imgui.draw_list_path_stroke(dim, false, 2.0)

                            imgui.set_cursor_screen_pos({ex + 12, ey - 8})
                            imgui.text_colored(string.format("◄ %s %dm (%.0f°)", sname, dist_m, S.last_proj.angle), dim)
                        end
                    end
                end

                imgui.end_window()
            end
            imgui.pop_style_var()
        end)
    end)
end

clog("初期化完了: HMD視線基準 JHMCS Plan C (常時描画版) が正常に起動しました")
