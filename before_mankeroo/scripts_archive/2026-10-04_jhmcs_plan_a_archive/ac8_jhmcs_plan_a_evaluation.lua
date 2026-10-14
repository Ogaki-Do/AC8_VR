-- ============================================================================
-- ac8_jhmcs_v1.lua : JHMCS プランA (JhmcsA) 実装・ロギング・デバッグ・評価スクリプト
--   ゲーム: 『ACE COMBAT 8』
--   目的:
--     1. UEVR公式リフレクションAPIによるカメラコンポーネント深層解析
--     2. on_early_calculate_stereo_view_offset によるVR視界回転の動的観測
--     3. プランA（PCM自由旋回 + UEVR視界逆補正）のリアルタイム検証
--     4. ImGuiリアルタイムモニタリング＆評価トグルUI
-- ============================================================================

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME    = "AC8-JHMCS-A"
local LOG_FILE_PATH  = "data/ac8_jhmcs_a_investigation.txt"

local log_file = nil
local pcall_ok, f = pcall(function() return io.open(LOG_FILE_PATH, "w") end)
if pcall_ok and f then
    log_file = f
    log_file:write(string.format("================================================================================\n"))
    log_file:write(string.format("  ACE COMBAT 8 - JHMCS プランA (JhmcsA) 評価 & テレメトリログ\n"))
    log_file:write(string.format("  開始日時: %s\n", os.date("%Y-%m-%d %H:%M:%S")))
    log_file:write(string.format("================================================================================\n\n"))
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

local S = {
    frame = 0,
    is_in_flight = false,
    dumped_reflection = false,

    pawn = nil,
    pc = nil,
    pcm = nil,

    cockpit_cam = nil,
    cockpit_input = nil,
    focus_comp = nil,

    plane_rot = { Pitch = 0, Yaw = 0, Roll = 0 },
    pcm_rot   = { Pitch = 0, Yaw = 0, Roll = 0 },
    stereo_rot = { Pitch = 0, Yaw = 0, Roll = 0 },
    diff_yaw  = 0.0,
    diff_pitch = 0.0,

    plan_a_compensate_enabled = false,
    compensation_applied_count = 0,
    can_write_rotator = nil,
}

local function get_name(obj)
    if not obj then return "None" end
    local ok, fn = pcall(function() return obj:get_full_name() end)
    if ok and fn then return fn:match("([^.]+)$") or fn end
    return tostring(obj)
end

-- ============================================================================
-- 1. UEVR公式リフレクションAPIによる深層プロパティ・関数走査
-- ============================================================================
local function dump_uobject_reflection(obj, label)
    if not obj then return end
    label = label or get_name(obj)

    local c = nil
    pcall(function() c = obj:get_class() end)
    if not c then return end

    clog("\n--------------------------------------------------------------------------------")
    clog("【%s】クラスリフレクション解析 (Class: %s)", label, get_name(c))
    clog("--------------------------------------------------------------------------------")

    local seen_props = {}
    local seen_funcs = {}
    local curr = c
    local depth = 0

    while curr and depth < 5 do
        local ok_p, prop = pcall(function() return curr:get_child_properties() end)
        if ok_p and prop then
            while prop do
                local ok_name, fn = pcall(function() return prop:get_fname():to_string() end)
                if ok_name and fn and not seen_props[fn] then
                    seen_props[fn] = true
                    local l = fn:lower()
                    if l:find("yaw") or l:find("pitch") or l:find("roll") or
                       l:find("limit") or l:find("clamp") or l:find("rot") or
                       l:find("input") or l:find("look") or l:find("target") or
                       l:find("speed") or l:find("angle") or l:find("view") or
                       l:find("buse") or l:find("active") or l:find("fov") then
                        local ok_v, val = pcall(function() return obj[fn] end)
                        local val_str = tostring(val)
                        if ok_v and type(val) == "number" then
                            val_str = string.format("%.3f", val)
                        end
                        clog("  [Prop] %-35s = %s", fn, val_str)
                    end
                end
                local ok_next, next_p = pcall(function() return prop:get_next() end)
                prop = (ok_next and next_p) or nil
            end
        end

        local ok_c, child = pcall(function() return curr:get_children() end)
        if ok_c and child then
            while child do
                local ok_name, fn = pcall(function() return child:get_fname():to_string() end)
                if ok_name and fn and not seen_funcs[fn] then
                    seen_funcs[fn] = true
                    local l = fn:lower()
                    if l:find("yaw") or l:find("pitch") or l:find("roll") or
                       l:find("look") or l:find("camera") or l:find("input") or
                       l:find("rotate") or l:find("target") or l:find("view") or
                       l:find("reset") or l:find("set") then
                        clog("  [Func] %s()", fn)
                    end
                end
                local ok_next, next_c = pcall(function() return child:get_next() end)
                child = (ok_next and next_c) or nil
            end
        end

        local ok_super, sup = pcall(function() return curr:get_super_struct() end)
        curr = (ok_super and sup) or nil
        depth = depth + 1
    end
end

-- ============================================================================
-- 2. 初回コンポーネント特定 & リフレクションダンプ
-- ============================================================================
local function init_plane_reflection()
    if S.dumped_reflection or not S.pawn then return end

    clog("\n================================================================================")
    clog("【JHMCS プランA: 自機カメラ構造 & プロパティ全解析】")
    clog("================================================================================")

    local actor_comp_class = api:find_uobject("Class /Script/Engine.ActorComponent")
    local all_comps = S.pawn:call("K2_GetComponentsByClass", actor_comp_class) or {}

    for _, c in ipairs(all_comps) do
        local cname = c:get_full_name() or ""
        if cname:find("LiveCockpitCameraComponent", 1, true) then
            S.cockpit_cam = c
        elseif cname:find("CockpitCameraInput", 1, true) then
            S.cockpit_input = c
        elseif cname:find("FocusTarget", 1, true) then
            S.focus_comp = c
        end
    end

    if S.cockpit_input then
        dump_uobject_reflection(S.cockpit_input, "CockpitCameraInput (スティック入力処理)")
    end
    if S.cockpit_cam then
        dump_uobject_reflection(S.cockpit_cam, "CockpitCamera (コックピットカメラ本体)")
    end
    if S.pcm then
        dump_uobject_reflection(S.pcm, "PlayerCameraManager (ゲーム内実描画カメラ)")
    end

    clog("\n================================================================================")
    clog("  リフレクション解析完了。以下、プランA (JhmcsA) の動的評価を開始します...")
    clog("================================================================================\n")

    S.dumped_reflection = true
end

-- ============================================================================
-- 3. プランA コア: on_early_calculate_stereo_view_offset フック
--    ステレオ描画直前のカメラ回転を観測 & 評価トグルによる逆補正検証
-- ============================================================================
local cbs = uevr.sdk.callbacks
if cbs and cbs.on_early_calculate_stereo_view_offset ~= nil then
    cbs.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
        if not S.is_in_flight or not rotation then return end

        if view_index == 0 then
            pcall(function()
                S.stereo_rot.Pitch = rotation.Pitch or 0
                S.stereo_rot.Yaw   = rotation.Yaw or 0
                S.stereo_rot.Roll  = rotation.Roll or 0
            end)
        end
    end)
    clog("on_early_calculate_stereo_view_offset フック登録成功 (完全読取専用)")
end

-- ============================================================================
-- 4. ゲームループ監視 (on_post_engine_tick)
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

    if S.pawn ~= pawn then
        S.pawn = pawn
        S.dumped_reflection = false
        local pc = api:get_player_controller(0)
        S.pc = pc
        if pc then S.pcm = pc.PlayerCameraManager end
    end

    S.is_in_flight = true
    return true
end

if cbs and cbs.on_post_engine_tick ~= nil then
    cbs.on_post_engine_tick(function()
        S.frame = S.frame + 1

        if not check_flight_active() then return end

        if not S.dumped_reflection then
            init_plane_reflection()
        end

        pcall(function()
            local pr = S.pawn:call("K2_GetActorRotation")
            if pr then S.plane_rot = pr end
        end)

        if S.pcm then
            pcall(function()
                local cr = S.pcm:call("GetCameraRotation")
                if cr then S.pcm_rot = cr end
            end)
        end

        local dy = (S.pcm_rot.Yaw or 0) - (S.plane_rot.Yaw or 0)
        while dy > 180.0 do dy = dy - 360.0 end
        while dy < -180.0 do dy = dy + 360.0 end
        S.diff_yaw = dy

        local dp = (S.pcm_rot.Pitch or 0) - (S.plane_rot.Pitch or 0)
        S.diff_pitch = dp
    end)
end

-- ============================================================================
-- 5. ImGui リアルタイム評価コントロールパネル
-- ============================================================================
if cbs and cbs.on_draw_ui ~= nil then
    cbs.on_draw_ui(function()
        if not S.is_in_flight then return end

        pcall(function()
            if imgui ~= nil and imgui.text ~= nil then
                imgui.text("=== AC8 360 JHMCS Plan A Evaluation ===")
                imgui.text(string.format("Plane Rot:  P:%+6.1f  Y:%+6.1f  R:%+6.1f",
                    S.plane_rot.Pitch or 0, S.plane_rot.Yaw or 0, S.plane_rot.Roll or 0))
                imgui.text(string.format("PCM Rot:    P:%+6.1f  Y:%+6.1f  R:%+6.1f",
                    S.pcm_rot.Pitch or 0, S.pcm_rot.Yaw or 0, S.pcm_rot.Roll or 0))
                imgui.text(string.format("Stereo Rot: P:%+6.1f  Y:%+6.1f  R:%+6.1f",
                    S.stereo_rot.Pitch or 0, S.stereo_rot.Yaw or 0, S.stereo_rot.Roll or 0))
                imgui.text(string.format("FreeLook Yaw Diff:  %+6.1f deg", S.diff_yaw))
            end
        end)
    end)
end

clog("%s 初期化完了 (プランA 評価システム稼働中)", SCRIPT_NAME)
