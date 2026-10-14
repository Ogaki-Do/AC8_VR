-- ============================================================================
-- ac8_jhmcs_v1.lua : JHMCS (Joint Helmet Mounted Cueing System) ローダー & メイン
-- ============================================================================

local api = uevr.api
if api == nil then return end

local CORE_FILE = "scripts/ac8_jhmcs_core.lua"
local core = nil

local function load_core()
    local ok, res = pcall(function() return dofile(CORE_FILE) end)
    if ok and res and type(res) == "table" then
        core = res
        print("[AC8-JHMCS] ac8_jhmcs_core.lua ロード成功")
    else
        print("[AC8-JHMCS] ac8_jhmcs_core.lua ロード失敗/待機中: " .. tostring(res))
    end
end

load_core()

-- 1. HMD姿勢コールバック
local cbs = uevr.sdk.callbacks
if cbs and cbs.on_post_calculate_stereo_view_offset ~= nil then
    pcall(function()
        cbs.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
            if core and position and rotation then
                local p = rotation.Pitch or rotation.x or 0
                local y = rotation.Yaw   or rotation.y or 0
                local r = rotation.Roll  or rotation.z or 0

                core.S.head_pos.x = position.X or position.x or 0
                core.S.head_pos.y = position.Y or position.y or 0
                core.S.head_pos.z = position.Z or position.z or 0

                core.S.head_rot.pitch = p
                core.S.head_rot.yaw = y
                core.S.head_rot.roll = r

                core.update_gaze_vectors(p, y, r)
            end
        end)
    end)
end

-- 2. メインフレーム処理
local frame_cnt = 0
if cbs and cbs.on_post_engine_tick ~= nil then
    cbs.on_post_engine_tick(function()
        frame_cnt = frame_cnt + 1
        -- 定期的なホットリロードチェック（コア未ロード時）
        if (not core) and (frame_cnt % 120 == 0) then
            load_core()
        end

        if core and core.tick then
            pcall(core.tick)
        end
    end)
end

-- 3. JHMCS バイザーHUD描画（360度全方位ターゲットボックス）
if cbs and cbs.on_draw_ui ~= nil then
    cbs.on_draw_ui(function()
        if core and core.on_draw_ui then
            pcall(core.on_draw_ui)
        end
    end)
end

print("[AC8-JHMCS] JHMCS v1 初期化完了")
