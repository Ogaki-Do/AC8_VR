-- ============================================================================
-- ac8_landing_hud_logger.lua
-- 『ACE COMBAT 8』 UEVR 着陸ミッション HUD・姿勢指示器消失 検証ロガー
--
-- 【目的】
--   着陸のあるミッションにおいて「HUDや姿勢指示器（人工水平儀・ピッチラダー・
--   速度計・高度計・速度ベクトル等）がどのタイミングで、何が起きて視界から
--   消えるのか」を完全解明するための診断・解析スクリプト。
--
-- 【検証・監視項目】
--   1. 姿勢指示器（Altimeter, PitchMeter, Velocity, LandingGuide 等）の
--      RenderTransform座標 (X, Y)、スケール、回転角のリアルタイム追跡
--   2. 座標の「急変（ジャンプ）」「画面外への吹き飛び (|X|,|Y| > 3000)」の自動検知
--   3. CanvasSlot の LayoutData / Offsets（ゲーム本体による配置座標変更）の検知
--   4. 可視性 (GetVisibility) と Viewport所属 (IsInViewport) の変化検知
--   5. 機体 Pawn / カメラの切り替え・喪失（着陸シネマティック突入など）の検知
--   6. 着陸関連ウィジェット（*Landing*, *Runway*, *ILS*, *Approach* 等）の出現検知
--   7. [F8] キー or UEVRメニュー内の「FORCE DUMP NOW」ボタンによる手動即時フルダンプ
--
-- 【ログ出力先】
--   data/landing_hud_debug_log.txt
-- ============================================================================

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME     = "AC8-LANDING-LOGGER"
local SCRIPT_VERSION  = "v1.0"
local LOG_FILE_PATH   = "data/landing_hud_debug_log.txt"

-- --------------------------------------------------------------------------
-- 1. ファイル I/O とロギング基盤
-- --------------------------------------------------------------------------
local log_file = nil
local function init_logfile()
    local ok, f = pcall(function() return io.open(LOG_FILE_PATH, "a") end)
    if ok and f then
        log_file = f
        log_file:write("\n================================================================================\n")
        log_file:write(string.format("  [%s %s] 着陸HUD・姿勢指示器 消失検証セッション開始: %s\n", 
            SCRIPT_NAME, SCRIPT_VERSION, os.date("%Y-%m-%d %H:%M:%S")))
        log_file:write("================================================================================\n")
        log_file:flush()
    end
end
init_logfile()

local function log_raw(str)
    print(string.format("[%s] %s", SCRIPT_NAME, str))
    if log_file then
        pcall(function()
            log_file:write(str .. "\n")
            log_file:flush()
        end)
    end
end

local function log(fmt, ...)
    local msg = string.format(fmt, ...)
    local t_str = os.date("%H:%M:%S")
    log_raw(string.format("[%s] %s", t_str, msg))
end

local function alert(tag, fmt, ...)
    local msg = string.format(fmt, ...)
    local t_str = os.date("%H:%M:%S")
    log_raw(string.format("[%s] ★★★【%s】★★★ %s", t_str, tag, msg))
end

-- --------------------------------------------------------------------------
-- 2. Windows API (GetAsyncKeyState: F8キー手動ダンプ用) の安全呼び出し
-- --------------------------------------------------------------------------
local get_async_keystate = nil
pcall(function()
    local ffi = require("ffi")
    ffi.cdef[[
        short GetAsyncKeyState(int vKey);
    ]]
    get_async_keystate = function(vkey)
        local ok, val = pcall(function() return ffi.C.GetAsyncKeyState(vkey) end)
        if ok and val and type(val) == "number" then
            -- 最上位ビット(0x8000)が立っていれば押されている
            return bit.band(val, 0x8000) ~= 0
        end
        return false
    end
end)

-- --------------------------------------------------------------------------
-- 3. 安全な UObject 呼び出しヘルパー
-- --------------------------------------------------------------------------
local function safe_call(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
end

local function full_name(obj)
    if not obj then return "nil" end
    return safe_call(function() return obj:get_full_name() end, "unknown")
end

local function short_name(obj)
    local fn = full_name(obj)
    return fn:match("([^.]+)$") or fn
end

local vis_names = {
    [0] = "Visible",
    [1] = "Collapsed",
    [2] = "Hidden",
    [3] = "HitTestInvisible",
    [4] = "SelfHitTestInvisible"
}

local function get_vis_str(vis)
    return vis_names[vis] or tostring(vis)
end

-- UWidget の状態（Visibility, IsInViewport, RenderOpacity）
local function get_widget_state(w)
    if not w then return nil end
    local vis = safe_call(function() return w:call("GetVisibility") end, -1)
    local inv = safe_call(function() return w:call("IsInViewport") end, false)
    local op  = safe_call(function() return w:call("GetRenderOpacity") end, 1.0)
    return {
        vis = vis,
        vis_str = get_vis_str(vis),
        in_viewport = inv,
        opacity = op
    }
end

-- UWidget の RenderTransform (Translation, Scale, Angle)
local function get_widget_rt(w)
    if not w then return nil end
    local ok, rt = pcall(function() return w:get_property("RenderTransform") end)
    if not ok or not rt then return nil end
    local ok_tr, tr = pcall(function() return rt.Translation end)
    local ok_sc, sc = pcall(function() return rt.Scale end)
    local ok_ang, ang = pcall(function() return rt.Angle end)
    return {
        tx = (ok_tr and tr and tr.X) or 0.0,
        ty = (ok_tr and tr and tr.Y) or 0.0,
        sx = (ok_sc and sc and sc.X) or 1.0,
        sy = (ok_sc and sc and sc.Y) or 1.0,
        angle = (ok_ang and ang) or 0.0,
    }
end

-- UWidget の CanvasSlot Offsets
local function get_slot_offsets(w)
    if not w then return nil end
    local ok, slot = pcall(function() return w:get_property("Slot") end)
    if not ok or not slot then return nil end
    local ok_ld, ld = pcall(function() return slot:get_property("LayoutData") end)
    if not ok_ld or not ld then return nil end
    local ok_off, off = pcall(function() return ld.Offsets end)
    if ok_off and off then
        return {
            left = off.Left or 0.0,
            top = off.Top or 0.0,
            right = off.Right or 0.0,
            bottom = off.Bottom or 0.0
        }
    end
    return nil
end

-- --------------------------------------------------------------------------
-- 4. 監視対象コンポーネント（姿勢指示器 ＆ HUD重要パーツ）
-- --------------------------------------------------------------------------
-- 監視するパーツのターゲット名リスト
local WATCH_TARGETS = {
    -- 姿勢指示器（ピッチラダー / 中央計器）
    { key = "Altimeter",             name = "Altimeter",             role = "姿勢指示器・中央計器(親)" },
    { key = "PitchMeter",           name = "PitchMeter",           role = "ピッチメーター" },
    { key = "Velocity",              name = "Velocity",              role = "速度ベクトル/滑移標" },
    { key = "VelocityIcon",          name = "VelocityIcon",          role = "速度ベクトル(W標)" },
    { key = "PitchBarLeft",          name = "PitchBarLeft",          role = "ピッチバー左" },
    { key = "PitchBarRight",         name = "PitchBarRight",         role = "ピッチバー右" },
    { key = "Neutral_L",             name = "Neutral_L",             role = "水平基準バー" },
    
    -- 着陸誘導系（着陸ミッションでゲーム本体が操作する可能性大）
    { key = "LandingGuide",          name = "LandingGuide",          role = "着陸誘導コンテナ" },
    { key = "LandingGuideHorizontal",name = "LandingGuideHorizontal",role = "着陸誘導水平バー" },
    { key = "LandingGuideVertical",  name = "LandingGuideVertical",  role = "着陸誘導垂直バー" },
    
    -- HUDコンテナ・画面枠
    { key = "MainFlight",            name = "WBP_HUD_Chronicle_MainFlight", role = "HUDメインルート" },
    { key = "ChroniclePersistent",   name = "ChroniclePersistent",   role = "中央HUDコンテナ(Persistent)" },
    { key = "MainCanvas",            name = "MainCanvas",            role = "HUD主キャンバス" },
    { key = "WorldToScreenDrawCanvas",name="WorldToScreenDrawCanvas",role = "3D世界投影キャンバス" },
    { key = "DynamicDrawCanvas",     name = "DynamicDrawCanvas",     role = "動的描画キャンバス" },
    { key = "LowestPriorityDynamic", name = "LowestPriorityDynamicDrawCanvas", role = "全画面投影キャンバス" },
    { key = "GunReticle",            name = "GunReticle",            role = "中央固定レティクル" },
    { key = "RadarCircle",           name = "RadarCircleCanvasPanel",role = "レーダー円(アンカー)" },
}

-- 監視状態のキャッシュテーブル
local tracked_nodes = {}
for _, t in ipairs(WATCH_TARGETS) do
    tracked_nodes[t.key] = {
        def = t,
        obj = nil,
        last_found = false,
        last_vis = nil,
        last_inv = nil,
        last_op = nil,
        last_tx = 0.0,
        last_ty = 0.0,
        last_sx = 1.0,
        last_sy = 1.0,
        last_angle = 0.0,
        last_offsets = nil,
    }
end

-- --------------------------------------------------------------------------
-- 5. Pawn & カメラ情報の取得
-- --------------------------------------------------------------------------
local function get_pawn_info()
    local pawn = safe_call(function() return api:get_player_pawn() end, nil)
    if not pawn then
        pawn = safe_call(function() return api:get_local_pawn(0) end, nil)
    end
    if not pawn then
        local pc = safe_call(function() return api:get_player_controller(0) end, nil)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end
    
    if not pawn then
        return { valid = false, name = "None" }
    end
    
    local nm = full_name(pawn)
    local loc = safe_call(function() return pawn:get_property("K2_GetActorLocation") end, nil)
    if not loc then
        loc = safe_call(function() return pawn.RootComponent and pawn.RootComponent.RelativeLocation end, nil)
    end
    local rot = safe_call(function() return pawn:get_property("K2_GetActorRotation") end, nil)
    if not rot then
        rot = safe_call(function() return pawn.RootComponent and pawn.RootComponent.RelativeRotation end, nil)
    end
    
    return {
        valid = true,
        obj = pawn,
        name = nm,
        short = short_name(pawn),
        x = (loc and (loc.X or loc.x)) or 0.0,
        y = (loc and (loc.Y or loc.y)) or 0.0,
        z = (loc and (loc.Z or loc.z)) or 0.0,
        pitch = (rot and (rot.Pitch or rot.pitch)) or 0.0,
        yaw   = (rot and (rot.Yaw or rot.yaw)) or 0.0,
        roll  = (rot and (rot.Roll or rot.roll)) or 0.0,
    }
end

-- --------------------------------------------------------------------------
-- 6. 全ウィジェット走査・ノード再解決
-- --------------------------------------------------------------------------
local function resolve_tracked_nodes()
    local widget_class = safe_call(function() return api:find_uobject("Class /Script/UMG.Widget") end, nil)
    if not widget_class then return end
    
    local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
    if type(all_w) ~= "table" then return end
    
    for _, t in ipairs(WATCH_TARGETS) do
        local node = tracked_nodes[t.key]
        -- オブジェクトが生存しているか簡易チェック
        local alive = false
        if node.obj then
            local test_nm = safe_call(function() return node.obj:get_full_name() end, nil)
            if test_nm and test_nm:find("/Engine/Transient", 1, true) then
                alive = true
            end
        end
        
        if not alive then
            node.obj = nil
            for _, w in ipairs(all_w) do
                local fn = safe_call(function() return w:get_full_name() end, "")
                if fn:find("/Engine/Transient", 1, true) and not fn:find("Default__", 1, true) then
                    local leaf = fn:match("([^.]+)$") or ""
                    -- 末尾の _数字 を剥がした比較
                    local base = leaf:gsub("_%d+$", "")
                    if leaf == t.name or base == t.name or fn:find(t.name, 1, true) then
                        node.obj = w
                        break
                    end
                end
            end
        end
    end
end

-- --------------------------------------------------------------------------
-- 7. 手動フルダンプ関数 (F8 または UIボタンから実行)
-- --------------------------------------------------------------------------
local function do_full_snapshot_dump(trigger_reason)
    local t_now = os.date("%Y-%m-%d %H:%M:%S")
    log_raw("\n================================================================================")
    log_raw(string.format("  ★★★ [FULL SNAPSHOT DUMP] トリガー: %s (%s) ★★★", trigger_reason, t_now))
    log_raw("================================================================================")
    
    -- 1. Pawn & カメラ状態
    local pinfo = get_pawn_info()
    if pinfo.valid then
        log_raw(string.format("【機体/Pawn】 %s", pinfo.name))
        log_raw(string.format("  位置: (X=%.1f, Y=%.1f, Z=%.1f)  姿勢: (Pitch=%.2f°, Yaw=%.2f°, Roll=%.2f°)",
            pinfo.x, pinfo.y, pinfo.z, pinfo.pitch, pinfo.yaw, pinfo.roll))
    else
        log_raw("【機体/Pawn】 なし (nil / 非アクティブ)")
    end
    
    -- 2. UEVRの2Dモード設定（Cutscene Guard の動作確認）
    local vr = uevr.params and uevr.params.vr
    if vr and vr.get_mod_value then
        local m2d = safe_call(function() return vr:get_mod_value("VR_2DScreenMode") end, "unknown")
        local mth = safe_call(function() return vr:get_mod_value("VR_RenderingMethod") end, "unknown")
        log_raw(string.format("【UEVR状態】 VR_2DScreenMode=%s, VR_RenderingMethod=%s", tostring(m2d), tostring(mth)))
    end
    
    -- 3. 監視対象ウィジェット一覧の詳細座標・可視性
    log_raw("\n【監視対象ウィジェット 座標・可視性スナップショット】")
    log_raw(string.format("  %-16s | %-8s | %-12s | %-5s | %-15s | %-12s | %s",
        "Target", "Viewport", "Visibility", "Alpha", "RenderTransform(X,Y)", "Scale(X,Y)", "CanvasSlot Offsets(L,T,R,B)"))
    log_raw("  " .. string.rep("-", 100))
    
    resolve_tracked_nodes()
    
    for _, t in ipairs(WATCH_TARGETS) do
        local node = tracked_nodes[t.key]
        local w = node.obj
        if w then
            local st = get_widget_state(w)
            local rt = get_widget_rt(w)
            local off = get_slot_offsets(w)
            
            local inv_str = (st and tostring(st.in_viewport)) or "?"
            local vis_str = (st and st.vis_str) or "?"
            local op_str  = (st and string.format("%.2f", st.opacity)) or "?"
            local rt_str  = (rt and string.format("(%.1f, %.1f)", rt.tx, rt.ty)) or "none"
            local sc_str  = (rt and string.format("(%.2f, %.2f)", rt.sx, rt.sy)) or "none"
            local off_str = (off and string.format("(L=%.0f, T=%.0f, R=%.0f, B=%.0f)", off.left, off.top, off.right, off.bottom)) or "none"
            
            log_raw(string.format("  %-16s | %-8s | %-12s | %-5s | %-15s | %-12s | %s",
                t.key, inv_str, vis_str, op_str, rt_str, sc_str, off_str))
        else
            log_raw(string.format("  %-16s | 【未検出 / 存在しない】", t.key))
        end
    end
    
    -- 4. メモリ上の全 UserWidget の簡易一覧（新規着陸関連や不審なウィジェットの洗い出し）
    log_raw("\n【着陸・HUD関連ウィジェット 全数探索】")
    local widget_class = safe_call(function() return api:find_uobject("Class /Script/UMG.Widget") end, nil)
    if widget_class then
        local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
        local found_count = 0
        for _, w in ipairs(all_w) do
            local fn = safe_call(function() return w:get_full_name() end, "")
            if fn:find("/Engine/Transient", 1, true) and not fn:find("Default__", 1, true) then
                local lfn = fn:lower()
                -- 着陸・アプローチ・フライト・HUDに関連する単語
                if lfn:find("landing") or lfn:find("runway") or lfn:find("ils") 
                   or lfn:find("approach") or lfn:find("altimeter") or lfn:find("pitch")
                   or lfn:find("mainflight") or lfn:find("fade") or lfn:find("touchdown") then
                    
                    found_count = found_count + 1
                    local st = get_widget_state(w)
                    local rt = get_widget_rt(w)
                    local inv_str = (st and tostring(st.in_viewport)) or "?"
                    local vis_str = (st and st.vis_str) or "?"
                    local rt_str  = (rt and string.format("RT=(%.1f, %.1f)", rt.tx, rt.ty)) or ""
                    log_raw(string.format("  [%02d] InViewport=%-5s Vis=%-18s %-16s : %s",
                        found_count, inv_str, vis_str, rt_str, fn))
                end
            end
        end
        log_raw(string.format("  -> 関連ウィジェット合計: %d 件", found_count))
    end
    
    log_raw("================================================================================\n")
end

-- --------------------------------------------------------------------------
-- 8. 毎フレーム監視＆状態変化・座標急変のリアルタイム検知
-- --------------------------------------------------------------------------
local frame_count = 0
local last_pawn_name = nil
local last_pawn_valid = false
local last_summary_time = 0
local known_landing_widgets = {}

local function monitor_frame()
    frame_count = frame_count + 1
    
    -- A. F8キーの手動ダンプ判定
    if get_async_keystate and get_async_keystate(0x77) then -- 0x77 = VK_F8
        do_full_snapshot_dump("F8 キー押下")
    end
    
    -- B. 機体 Pawn 状態の監視
    local pinfo = get_pawn_info()
    if pinfo.valid ~= last_pawn_valid then
        if pinfo.valid then
            alert("PAWN-ACQUIRED", "機体 Pawn 検出: %s (Short: %s)", pinfo.name, pinfo.short)
            resolve_tracked_nodes()
        else
            alert("PAWN-LOST", "機体 Pawn が消失(nil)しました！ 前のPawn: %s", tostring(last_pawn_name))
        end
        last_pawn_valid = pinfo.valid
    elseif pinfo.valid and pinfo.name ~= last_pawn_name then
        alert("PAWN-SWITCHED", "機体 Pawn が切り替わりました: %s -> %s", tostring(last_pawn_name), pinfo.name)
        last_pawn_name = pinfo.name
        resolve_tracked_nodes()
    end
    last_pawn_name = pinfo.name
    
    -- 30フレーム（約0.5秒）に1回、ノード解決を更新
    if frame_count % 30 == 0 then
        resolve_tracked_nodes()
    end
    
    -- C. 監視対象ノードの座標・可視性変化の即時チェック
    for _, t in ipairs(WATCH_TARGETS) do
        local node = tracked_nodes[t.key]
        local w = node.obj
        
        if w then
            local st = get_widget_state(w)
            local rt = get_widget_rt(w)
            local off = get_slot_offsets(w)
            
            if st then
                -- 1. Viewport 離脱の検知
                if node.last_inv ~= nil and node.last_inv ~= st.in_viewport then
                    if not st.in_viewport then
                        alert("VIEWPORT-DROPPED", "【%s (%s)】が Viewport から外れました！ (true -> false)", t.key, t.role)
                    else
                        alert("VIEWPORT-ATTACHED", "【%s (%s)】が Viewport に追加されました！ (false -> true)", t.key, t.role)
                    end
                end
                node.last_inv = st.in_viewport
                
                -- 2. 可視性 (GetVisibility) 変化の検知
                if node.last_vis ~= nil and node.last_vis ~= st.vis then
                    alert("VISIBILITY-CHANGED", "【%s (%s)】の表示状態が変化: %s -> %s", 
                        t.key, t.role, get_vis_str(node.last_vis), st.vis_str)
                end
                node.last_vis = st.vis
                
                -- 3. 透明度 (RenderOpacity) 変化の検知
                if node.last_op ~= nil and math.abs(node.last_op - st.opacity) > 0.05 then
                    if st.opacity < 0.05 then
                        alert("OPACITY-ZERO", "【%s (%s)】が透明化しました！ Opacity: %.2f -> %.2f", 
                            t.key, t.role, node.last_op, st.opacity)
                    end
                end
                node.last_op = st.opacity
            end
            
            if rt then
                -- 4. 座標の急変（ジャンプ）検知 (|ΔX| > 30 または |ΔY| > 30)
                local dx = math.abs(rt.tx - node.last_tx)
                local dy = math.abs(rt.ty - node.last_ty)
                if node.last_found and (dx > 30.0 or dy > 30.0) then
                    alert("COORDS-JUMPED", "【%s (%s)】の RenderTransform 座標が急変！ 前=(%.1f, %.1f) -> 現=(%.1f, %.1f) [差: ΔX=%.1f, ΔY=%.1f]",
                        t.key, t.role, node.last_tx, node.last_ty, rt.tx, rt.ty, dx, dy)
                end
                
                -- 5. 画面外への吹き飛び検知 (|X| > 3000 または |Y| > 3000)
                if (math.abs(rt.tx) > 3000.0 or math.abs(rt.ty) > 3000.0) and 
                   (math.abs(node.last_tx) <= 3000.0 and math.abs(node.last_ty) <= 3000.0) then
                    alert("COORDS-OUT-OF-BOUNDS", "【%s (%s)】が画面外へ吹き飛びました！ 座標=(%.1f, %.1f)",
                        t.key, t.role, rt.tx, rt.ty)
                end
                
                -- 6. スケール急変検知
                if node.last_found and (math.abs(rt.sx - node.last_sx) > 0.3 or math.abs(rt.sy - node.last_sy) > 0.3) then
                    alert("SCALE-CHANGED", "【%s (%s)】のスケールが変化: (%.2f, %.2f) -> (%.2f, %.2f)",
                        t.key, t.role, node.last_sx, node.last_sy, rt.sx, rt.sy)
                end
                
                node.last_tx = rt.tx
                node.last_ty = rt.ty
                node.last_sx = rt.sx
                node.last_sy = rt.sy
                node.last_angle = rt.angle
            end
            
            -- 7. CanvasSlot Offsets (ゲーム本体によるレイアウト座標変更)
            if off and node.last_offsets then
                local d_l = math.abs(off.left - node.last_offsets.left)
                local d_t = math.abs(off.top - node.last_offsets.top)
                if d_l > 30.0 or d_t > 30.0 then
                    alert("SLOT-LAYOUT-JUMP", "【%s (%s)】の CanvasSlot Offsets が変化！ 前=(L=%.0f, T=%.0f) -> 現=(L=%.0f, T=%.0f)",
                        t.key, t.role, node.last_offsets.left, node.last_offsets.top, off.left, off.top)
                end
            end
            node.last_offsets = off
            node.last_found = true
        else
            if node.last_found then
                alert("NODE-LOST", "【%s (%s)】のインスタンスを喪失しました！", t.key, t.role)
                node.last_found = false
            end
        end
    end
    
    -- D. 着陸関連ウィジェットの新規出現スキャン（120フレーム＝約2秒に1回）
    if frame_count % 120 == 0 then
        local widget_class = safe_call(function() return api:find_uobject("Class /Script/UMG.Widget") end, nil)
        if widget_class then
            local all_w = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
            for _, w in ipairs(all_w) do
                local fn = safe_call(function() return w:get_full_name() end, "")
                if fn:find("/Engine/Transient", 1, true) and not fn:find("Default__", 1, true) then
                    local lfn = fn:lower()
                    if (lfn:find("landing") or lfn:find("runway") or lfn:find("ils") or lfn:find("approach")) 
                        and not known_landing_widgets[fn] then
                        known_landing_widgets[fn] = true
                        local st = get_widget_state(w)
                        alert("NEW-LANDING-WIDGET", "着陸関連ウィジェットが出現！ InViewport=%s Vis=%s : %s",
                            tostring(st and st.in_viewport), tostring(st and st.vis_str), fn)
                    end
                end
            end
        end
    end
    
    -- E. 定期ハートビートサマリー（10秒に1回、姿勢指示器の現在座標を1行記録）
    local now_t = os.time()
    if now_t - last_summary_time >= 10 then
        last_summary_time = now_t
        local alt_node = tracked_nodes["Altimeter"]
        local vel_node = tracked_nodes["Velocity"]
        local lg_node  = tracked_nodes["LandingGuide"]
        local mf_node  = tracked_nodes["MainFlight"]
        
        local alt_str = alt_node.obj and string.format("(%.0f,%.0f) Vis=%s Inv=%s", 
            alt_node.last_tx, alt_node.last_ty, get_vis_str(alt_node.last_vis), tostring(alt_node.last_inv)) or "Not Found"
        local vel_str = vel_node.obj and string.format("(%.0f,%.0f) Vis=%s Inv=%s", 
            vel_node.last_tx, vel_node.last_ty, get_vis_str(vel_node.last_vis), tostring(vel_node.last_inv)) or "Not Found"
        local lg_str  = lg_node.obj and string.format("Vis=%s Inv=%s", 
            get_vis_str(lg_node.last_vis), tostring(lg_node.last_inv)) or "Not Found"
        local mf_str  = mf_node.obj and string.format("Vis=%s Inv=%s", 
            get_vis_str(mf_node.last_vis), tostring(mf_node.last_inv)) or "Not Found"
            
        log("【定期生存】 Pawn=%s | Altimeter=%s | Velocity=%s | LandingGuide=%s | MainFlight=%s",
            tostring(pinfo.short), alt_str, vel_str, lg_str, mf_str)
    end
end

-- --------------------------------------------------------------------------
-- 9. UEVR コールバック登録
-- --------------------------------------------------------------------------
local cbs = uevr.sdk.callbacks

-- 毎フレームのエンジン後処理（高精度監視）
if cbs and cbs.on_post_engine_tick then
    cbs.on_post_engine_tick(function()
        pcall(monitor_frame)
    end)
end

-- UEVR メニュー内 UI（Insert キー）
if cbs and cbs.on_draw_ui then
    cbs.on_draw_ui(function()
        pcall(function()
            if imgui then
                imgui.text("=== ACE COMBAT 8 Landing HUD Logger ===")
                imgui.text("Status: Running (" .. SCRIPT_VERSION .. ")")
                imgui.text("Log: " .. LOG_FILE_PATH)
                imgui.separator()
                
                -- 手動フルダンプボタン
                if imgui.button("★ FORCE DUMP NOW (HUD消失時 手動ダンプ) ★") then
                    do_full_snapshot_dump("UEVRメニュー UIボタン押下")
                end
                imgui.text("※ゲーム内キーボード [F8] キーでも即時ダンプ可能です")
                
                imgui.separator()
                -- ★ HUD がない時に押す復帰ボタン
                if imgui.button("Restore Missing HUD (Press if HUD is Missing)") then
                    -- MainFlight を探して AddToViewport
                    pcall(function()
                        local uw_c = api:find_uobject("Class /Script/UMG.UserWidget")
                        if uw_c then
                            local arr = uw_c:get_objects_matching(false) or {}
                            for _, w in ipairs(arr) do
                                local fn = w:get_full_name()
                                if fn:find("WBP_HUD_Chronicle_MainFlight", 1, true) and fn:find("/Engine/Transient", 1, true) then
                                    w:AddToViewport(0)
                                    w:SetVisibility(0)
                                    w:SetRenderOpacity(1.0)
                                end
                                if fn:find("DynamicDrawCanvas", 1, true) or fn:find("LowestPriority", 1, true) then
                                    w:SetRenderOpacity(1.0)
                                    w:SetVisibility(4)
                                end
                            end
                        end
                    end)
                    resolve_tracked_nodes()
                end
                imgui.text("※ミッション28等でHUDが消えた場合、上記ボタンで強制復帰します")
                
                imgui.separator()
                -- リアルタイム簡易モニター表示
                local alt_node = tracked_nodes["Altimeter"]
                local vel_node = tracked_nodes["Velocity"]
                if alt_node.obj then
                    imgui.text(string.format("Altimeter (姿勢計): Pos=(%.1f, %.1f) Vis=%s Inv=%s",
                        alt_node.last_tx, alt_node.last_ty, get_vis_str(alt_node.last_vis), tostring(alt_node.last_inv)))
                else
                    imgui.text("Altimeter: Not detected")
                end
                
                if vel_node.obj then
                    imgui.text(string.format("Velocity (W標): Pos=(%.1f, %.1f) Vis=%s Inv=%s",
                        vel_node.last_tx, vel_node.last_ty, get_vis_str(vel_node.last_vis), tostring(vel_node.last_inv)))
                else
                    imgui.text("Velocity: Not detected")
                end
            end
        end)
    end)
end

log("★★★ 着陸HUD・姿勢指示器 検証ロガー (%s) 初期化完了 ★★★", SCRIPT_VERSION)
log("  監視対象: Altimeter, PitchMeter, Velocity, LandingGuide, MainFlight 等")
log("  ショートカット: [F8] キー、または Insert メニューのボタンで即時フルダンプ可能です")
